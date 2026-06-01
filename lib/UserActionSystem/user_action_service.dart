// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/MarkdownSystem/markdown_parser.dart';
import 'package:noetec/MarkdownSystem/markdown_serializer.dart';
import 'package:noetec/UserActionSystem/user_action.dart';

class UserActionService {
  final OpenedDocumentsManager _documentsManager;
  final IdService _idService;

  UserActionService(this._documentsManager, this._idService);

  void handleAction(UserAction action) {
    switch (action) {
      case InsertText():
        _handleInsertText(action);
      case ClickOnTextBlock():
        _handleClickOnTextBlock(action);
      case SplitTextBlock():
        _handleSplitTextBlock(action);
      case DeleteTextBack():
        _handleDeleteTextBack(action);
      case DeleteTextForward():
        _handleDeleteTextForward(action);
      case MoveCursor():
        _handleMoveCursor(action);
      case ReplaceText():
        _handleReplaceText(action);
      case SetCursorPosition():
        _handleSetCursorPosition(action);
      case ExtendSelection():
        _handleExtendSelection(action);
      case SetRangeSelection():
        _handleSetRangeSelection(action);
      case SelectAll():
        _handleSelectAll(action);
      case DeleteSelection():
        _handleDeleteSelection(action);
      case Paste():
        _handlePaste(action);
    }
  }

  void _handleInsertText(InsertText action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    final insertionPos = block.cursorPosFromFlatOffset(action.flatOffset);
    final segment = block.segments.value[insertionPos.segmentIndex];
    final newText = segment.text.replaceRange(
      insertionPos.offset,
      insertionPos.offset,
      action.text,
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments.value);
    newSegments[insertionPos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    final newFlatOffset = action.flatOffset + action.text.length;
    final newCursorPos = block.cursorPosFromFlatOffset(newFlatOffset);

    document.selection.value = SingleCursorSelectionState(
      cursorPos: newCursorPos,
    );
  }

  void _handleClickOnTextBlock(ClickOnTextBlock action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: CursorPositionInTextBlock(
        blockId: action.blockId,
        segmentIndex: action.segmentIndex,
        offset: action.offset,
      ),
    );
  }

  void _handleSetCursorPosition(SetCursorPosition action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(action.flatOffset),
    );
  }

  void _handleDeleteTextBack(DeleteTextBack action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    if (action.flatOffset <= 0) {
      // Cursor is at the start of the block — merge with the previous block.
      final ids = document.flatBlockIds();
      final idx = ids.indexOf(action.blockId);
      if (idx <= 0) return; // No previous block — no-op.

      final prevBlock = document.getBlockById(ids[idx - 1]);
      if (prevBlock is! TextBlock) return;

      // rightBlock = current (cursor block, keeps its ID on non-empty merge)
      // leftBlock  = previous
      _mergeAdjacentBlocks(
        document: document,
        leftBlock: prevBlock,
        rightBlock: block,
        cursorBlock: block,
      );
      return;
    }

    // The character to delete is at flatOffset - 1.
    final deletePos = block.charPosFromFlatOffset(action.flatOffset - 1);
    if (deletePos == null) return;

    final segment = block.segments.value[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset,
      deletePos.offset + 1,
      '',
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments.value);
    newSegments[deletePos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    final newFlatOffset = action.flatOffset - 1;
    final newCursorPos = block.cursorPosFromFlatOffset(newFlatOffset);

    document.selection.value = SingleCursorSelectionState(
      cursorPos: newCursorPos,
    );
  }

  void _handleDeleteTextForward(DeleteTextForward action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    final totalLength = block.computeAllSegmentsText().length;
    if (action.flatOffset >= totalLength) {
      // Cursor is at the end of the block — merge with the next block.
      final ids = document.flatBlockIds();
      final idx = ids.indexOf(action.blockId);
      if (idx == -1 || idx >= ids.length - 1) return; // No next block — no-op.

      final nextBlock = document.getBlockById(ids[idx + 1]);
      if (nextBlock is! TextBlock) return;

      // leftBlock  = current (cursor block, keeps its ID on non-empty merge)
      // rightBlock = next
      _mergeAdjacentBlocks(
        document: document,
        leftBlock: block,
        rightBlock: nextBlock,
        cursorBlock: block,
      );
      return;
    }

    // The character to delete is at flatOffset (the one right after the cursor).
    final deletePos = block.charPosFromFlatOffset(action.flatOffset);
    if (deletePos == null) return;

    final segment = block.segments.value[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset,
      deletePos.offset + 1,
      '',
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments.value);
    newSegments[deletePos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    // Cursor stays at the same flat offset.
    final newCursorPos = block.cursorPosFromFlatOffset(action.flatOffset);

    document.selection.value = SingleCursorSelectionState(
      cursorPos: newCursorPos,
    );
  }

  /// Merges [leftBlock] and [rightBlock] into a single block.
  ///
  /// [cursorBlock] is the block where the cursor currently resides — it keeps
  /// its ID when both blocks are non-empty (the other block is removed).
  ///
  /// Rules:
  ///   • If [leftBlock] is empty: remove it, cursor stays in [rightBlock] at
  ///     offset 0.
  ///   • If [rightBlock] is empty: remove it, cursor stays in [leftBlock] at
  ///     the end.
  ///   • If both non-empty: append all segments from the removed block onto
  ///     [cursorBlock]; remove the other block; place cursor at the join point
  ///     (offset = length of left block text before merge).
  void _mergeAdjacentBlocks({
    required DocumentModel document,
    required TextBlock leftBlock,
    required TextBlock rightBlock,
    required TextBlock cursorBlock,
  }) {
    final leftText = leftBlock.computeAllSegmentsText();
    final leftEmpty = leftText.isEmpty;
    final rightEmpty = rightBlock.computeAllSegmentsText().isEmpty;

    if (leftEmpty) {
      // Remove the empty left block; cursor stays in rightBlock at offset 0.
      document.removeBlock(leftBlock.id);
      document.selection.value = SingleCursorSelectionState(
        cursorPos: rightBlock.cursorPosFromFlatOffset(0),
      );
      return;
    }

    if (rightEmpty) {
      // Remove the empty right block; cursor stays in leftBlock at its end.
      document.removeBlock(rightBlock.id);
      document.selection.value = SingleCursorSelectionState(
        cursorPos: leftBlock.cursorPosFromFlatOffset(leftText.length),
      );
      return;
    }

    // Both non-empty: merge into cursorBlock and remove the other.
    final joinOffset = leftText.length;
    final otherBlock = cursorBlock == leftBlock ? rightBlock : leftBlock;
    final mergedSegments = [
      ...leftBlock.segments.value,
      ...rightBlock.segments.value,
    ];

    cursorBlock.segments.replaceRange(
      0,
      cursorBlock.segments.length,
      mergedSegments,
    );
    document.removeBlock(otherBlock.id);

    document.selection.value = SingleCursorSelectionState(
      cursorPos: cursorBlock.cursorPosFromFlatOffset(joinOffset),
    );
  }

  void _handleMoveCursor(MoveCursor action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // When a range selection is active, Arrow without Shift collapses it.
    if (selection is RangeSelectionState) {
      final anchor = selection.anchor;
      final extent = selection.extent;
      if (anchor is! CursorPositionInTextBlock ||
          extent is! CursorPositionInTextBlock) {
        return;
      }

      // Determine which end is "earlier" in the document.
      final (first, last) = _orderedCursors(document, anchor, extent);
      if (first == null || last == null) return;

      switch (action.direction) {
        case CursorMoveDirection.left:
          document.selection.value = SingleCursorSelectionState(
            cursorPos: first,
          );
        case CursorMoveDirection.right:
          document.selection.value = SingleCursorSelectionState(
            cursorPos: last,
          );
      }
      return;
    }

    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final totalLength = block.computeAllSegmentsText().length;

    switch (action.direction) {
      case CursorMoveDirection.left:
        if (flatOffset > 0) {
          document.selection.value = SingleCursorSelectionState(
            cursorPos: block.cursorPosFromFlatOffset(flatOffset - 1),
          );
        } else {
          _moveToPreviousBlock(document, cursor.blockId);
        }

      case CursorMoveDirection.right:
        if (flatOffset < totalLength) {
          document.selection.value = SingleCursorSelectionState(
            cursorPos: block.cursorPosFromFlatOffset(flatOffset + 1),
          );
        } else {
          _moveToNextBlock(document, cursor.blockId);
        }
    }
  }

  void _moveToPreviousBlock(DocumentModel document, String currentBlockId) {
    final ids = document.flatBlockIds();
    final idx = ids.indexOf(currentBlockId);
    if (idx <= 0) return;

    final prevBlock = document.getBlockById(ids[idx - 1]);
    if (prevBlock is! TextBlock) return;

    final endOffset = prevBlock.computeAllSegmentsText().length;
    document.selection.value = SingleCursorSelectionState(
      cursorPos: prevBlock.cursorPosFromFlatOffset(endOffset),
    );
  }

  void _moveToNextBlock(DocumentModel document, String currentBlockId) {
    final ids = document.flatBlockIds();
    final idx = ids.indexOf(currentBlockId);
    if (idx == -1 || idx >= ids.length - 1) return;

    final nextBlock = document.getBlockById(ids[idx + 1]);
    if (nextBlock is! TextBlock) return;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: nextBlock.cursorPosFromFlatOffset(0),
    );
  }

  // ---------------------------------------------------------------------------
  // Selection actions
  // ---------------------------------------------------------------------------

  void _handleExtendSelection(ExtendSelection action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final selection = document.selection.value;

    CursorPositionInTextBlock anchor;
    CursorPositionInTextBlock extent;

    if (selection is SingleCursorSelectionState) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
      extent = cursor;
    } else if (selection is RangeSelectionState) {
      if (selection.anchor is! CursorPositionInTextBlock ||
          selection.extent is! CursorPositionInTextBlock) {
        return;
      }
      anchor = selection.anchor as CursorPositionInTextBlock;
      extent = selection.extent as CursorPositionInTextBlock;
    } else {
      return;
    }

    // Move the extent by one character in the given direction.
    final newExtent = _moveCursorPosition(document, extent, action.direction);
    if (newExtent == null) return; // Already at document boundary.

    // If anchor == newExtent, collapse to single cursor.
    if (anchor == newExtent) {
      document.selection.value = SingleCursorSelectionState(cursorPos: anchor);
    } else {
      document.selection.value = RangeSelectionState(
        anchor: anchor,
        extent: newExtent,
      );
    }
  }

  void _handleSetRangeSelection(SetRangeSelection action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final anchorPos = CursorPositionInTextBlock(
      blockId: action.anchorBlockId,
      segmentIndex: action.anchorSegmentIndex,
      offset: action.anchorOffset,
    );
    final extentPos = CursorPositionInTextBlock(
      blockId: action.extentBlockId,
      segmentIndex: action.extentSegmentIndex,
      offset: action.extentOffset,
    );

    if (anchorPos == extentPos) {
      document.selection.value = SingleCursorSelectionState(
        cursorPos: anchorPos,
      );
    } else {
      document.selection.value = RangeSelectionState(
        anchor: anchorPos,
        extent: extentPos,
      );
    }
  }

  void _handleSelectAll(SelectAll action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final ids = document.flatBlockIds();
    if (ids.isEmpty) return;

    final firstBlock = document.getBlockById(ids.first);
    final lastBlock = document.getBlockById(ids.last);
    if (firstBlock is! TextBlock || lastBlock is! TextBlock) return;

    final anchor = firstBlock.cursorPosFromFlatOffset(0);
    final lastText = lastBlock.computeAllSegmentsText();
    final extent = lastBlock.cursorPosFromFlatOffset(lastText.length);

    if (anchor == extent) {
      // Document is empty (single empty block).
      document.selection.value = SingleCursorSelectionState(cursorPos: anchor);
    } else {
      document.selection.value = RangeSelectionState(
        anchor: anchor,
        extent: extent,
      );
    }
  }

  void _handleDeleteSelection(DeleteSelection action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! RangeSelectionState) return;

    final anchor = selection.anchor;
    final extent = selection.extent;
    if (anchor is! CursorPositionInTextBlock ||
        extent is! CursorPositionInTextBlock) {
      return;
    }

    // Determine document order: first (earlier) and last (later).
    final (first, last) = _orderedCursors(document, anchor, extent);
    if (first == null || last == null) return;

    if (first.blockId == last.blockId) {
      _deleteSelectionSingleBlock(document, first, last);
    } else {
      _deleteSelectionMultiBlock(document, first, last);
    }
  }

  /// Deletes selected range within a single block.
  void _deleteSelectionSingleBlock(
    DocumentModel document,
    CursorPositionInTextBlock first,
    CursorPositionInTextBlock last,
  ) {
    final block = document.getBlockById(first.blockId);
    if (block is! TextBlock) return;

    final firstFlat = block.flatOffsetFromCursor(
      first.segmentIndex,
      first.offset,
    );
    final lastFlat = block.flatOffsetFromCursor(last.segmentIndex, last.offset);

    if (firstFlat == lastFlat) return; // Nothing to delete.

    final segs = block.segments.value;

    // Split at lastFlat → (beforeLast, afterLast).
    final (beforeLast, afterLast) = splitSegmentsAt(segs, lastFlat);
    // Split beforeLast at firstFlat → (beforeFirst, selected).
    final (beforeFirst, _) = splitSegmentsAt(beforeLast, firstFlat);

    // Result: beforeFirst + afterLast.
    final newSegs = [...beforeFirst, ...afterLast];
    final filtered = newSegs.where((s) => s.text.isNotEmpty).toList();
    final normalized = filtered.isEmpty
        ? [const TextSegment(text: '')]
        : filtered;

    block.segments.replaceRange(0, block.segments.length, normalized);

    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(firstFlat),
    );
  }

  /// Deletes selected range spanning multiple blocks.
  void _deleteSelectionMultiBlock(
    DocumentModel document,
    CursorPositionInTextBlock first,
    CursorPositionInTextBlock last,
  ) {
    final firstBlock = document.getBlockById(first.blockId);
    final lastBlock = document.getBlockById(last.blockId);
    if (firstBlock is! TextBlock || lastBlock is! TextBlock) return;

    final firstFlat = firstBlock.flatOffsetFromCursor(
      first.segmentIndex,
      first.offset,
    );
    final lastFlat = lastBlock.flatOffsetFromCursor(
      last.segmentIndex,
      last.offset,
    );

    // 1. Trim firstBlock: keep only text before the selection start.
    final (keepBefore, _) = splitSegmentsAt(
      firstBlock.segments.value,
      firstFlat,
    );

    // 2. Trim lastBlock: keep only text after the selection end.
    final (_, keepAfter) = splitSegmentsAt(lastBlock.segments.value, lastFlat);

    // 3. Remove all intermediate blocks (between first and last).
    final ids = document.flatBlockIds();
    final firstIdx = ids.indexOf(first.blockId);
    final lastIdx = ids.indexOf(last.blockId);
    // Remove from last to first to avoid index shifting.
    for (var i = lastIdx - 1; i > firstIdx; i--) {
      document.removeBlock(ids[i]);
    }

    // 4. Merge remaining: keepBefore + keepAfter → firstBlock; remove lastBlock.
    final mergedSegs = [...keepBefore, ...keepAfter];
    final filtered = mergedSegs.where((s) => s.text.isNotEmpty).toList();
    final normalized = filtered.isEmpty
        ? [const TextSegment(text: '')]
        : filtered;

    firstBlock.segments.replaceRange(0, firstBlock.segments.length, normalized);
    document.removeBlock(lastBlock.id);

    // 5. Cursor at the join point.
    document.selection.value = SingleCursorSelectionState(
      cursorPos: firstBlock.cursorPosFromFlatOffset(firstFlat),
    );
  }

  // ---------------------------------------------------------------------------
  // Cursor movement helpers
  // ---------------------------------------------------------------------------

  /// Moves a cursor position by one character in [direction], crossing block
  /// boundaries when needed. Returns `null` if already at the document boundary.
  CursorPositionInTextBlock? _moveCursorPosition(
    DocumentModel document,
    CursorPositionInTextBlock cursor,
    CursorMoveDirection direction,
  ) {
    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return null;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final totalLength = block.computeAllSegmentsText().length;

    switch (direction) {
      case CursorMoveDirection.left:
        if (flatOffset > 0) {
          return block.cursorPosFromFlatOffset(flatOffset - 1);
        }
        // Cross to previous block.
        final ids = document.flatBlockIds();
        final idx = ids.indexOf(cursor.blockId);
        if (idx <= 0) return null;
        final prevBlock = document.getBlockById(ids[idx - 1]);
        if (prevBlock is! TextBlock) return null;
        return prevBlock.cursorPosFromFlatOffset(
          prevBlock.computeAllSegmentsText().length,
        );

      case CursorMoveDirection.right:
        if (flatOffset < totalLength) {
          return block.cursorPosFromFlatOffset(flatOffset + 1);
        }
        // Cross to next block.
        final ids = document.flatBlockIds();
        final idx = ids.indexOf(cursor.blockId);
        if (idx == -1 || idx >= ids.length - 1) return null;
        final nextBlock = document.getBlockById(ids[idx + 1]);
        if (nextBlock is! TextBlock) return null;
        return nextBlock.cursorPosFromFlatOffset(0);
    }
  }

  /// Returns two cursor positions ordered by their document position:
  /// (first, last) where first appears earlier in the document.
  /// Returns (null, null) if ordering cannot be determined.
  (CursorPositionInTextBlock?, CursorPositionInTextBlock?) _orderedCursors(
    DocumentModel document,
    CursorPositionInTextBlock a,
    CursorPositionInTextBlock b,
  ) {
    if (a.blockId == b.blockId) {
      final block = document.getBlockById(a.blockId);
      if (block is! TextBlock) return (null, null);
      final flatA = block.flatOffsetFromCursor(a.segmentIndex, a.offset);
      final flatB = block.flatOffsetFromCursor(b.segmentIndex, b.offset);
      return flatA <= flatB ? (a, b) : (b, a);
    }

    final ids = document.flatBlockIds();
    final idxA = ids.indexOf(a.blockId);
    final idxB = ids.indexOf(b.blockId);
    if (idxA == -1 || idxB == -1) return (null, null);
    return idxA < idxB ? (a, b) : (b, a);
  }

  // ---------------------------------------------------------------------------
  // Clipboard helpers
  // ---------------------------------------------------------------------------

  /// Extracts the currently selected content as a markdown string.
  ///
  /// Returns `null` if there is no range selection.
  /// This is a read-only operation — it does not modify the document.
  String? extractSelectedMarkdown(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return null;

    final selection = document.selection.value;
    if (selection is! RangeSelectionState) return null;

    final anchor = selection.anchor;
    final extent = selection.extent;
    if (anchor is! CursorPositionInTextBlock ||
        extent is! CursorPositionInTextBlock) {
      return null;
    }

    final (first, last) = _orderedCursors(document, anchor, extent);
    if (first == null || last == null) return null;

    if (first.blockId == last.blockId) {
      // Single block selection.
      final block = document.getBlockById(first.blockId);
      if (block is! TextBlock) return null;

      final firstFlat = block.flatOffsetFromCursor(
        first.segmentIndex,
        first.offset,
      );
      final lastFlat = block.flatOffsetFromCursor(
        last.segmentIndex,
        last.offset,
      );

      return blocksToMarkdown([block], ranges: [(firstFlat, lastFlat)]);
    }

    // Multi-block selection.
    final ids = document.flatBlockIds();
    final firstIdx = ids.indexOf(first.blockId);
    final lastIdx = ids.indexOf(last.blockId);

    final blocks = <TextBlock>[];
    final ranges = <(int, int)?>[];

    for (var i = firstIdx; i <= lastIdx; i++) {
      final block = document.getBlockById(ids[i]);
      if (block is! TextBlock) continue;

      if (i == firstIdx) {
        final firstFlat = block.flatOffsetFromCursor(
          first.segmentIndex,
          first.offset,
        );
        blocks.add(block);
        ranges.add((firstFlat, block.computeAllSegmentsText().length));
      } else if (i == lastIdx) {
        final lastFlat = block.flatOffsetFromCursor(
          last.segmentIndex,
          last.offset,
        );
        blocks.add(block);
        ranges.add((0, lastFlat));
      } else {
        blocks.add(block);
        ranges.add(null); // Full block.
      }
    }

    return blocksToMarkdown(blocks, ranges: ranges);
  }

  void _handlePaste(Paste action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    // If there is a range selection, delete it first.
    if (document.selection.value is RangeSelectionState) {
      _handleDeleteSelection(DeleteSelection(documentId: action.documentId));
    }

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final parsedBlocks = markdownToBlocks(
      action.clipboardContent,
      idService: _idService,
      documentId: action.documentId,
    );

    if (parsedBlocks.isEmpty) return;

    if (parsedBlocks.length == 1) {
      // Single block paste: insert segments at cursor position.
      _insertSegmentsAtCursor(
        document,
        cursor,
        parsedBlocks.first.segments.value,
      );
    } else {
      // Multi-block paste: split current block and insert new blocks.
      _insertBlocksAtCursor(document, cursor, parsedBlocks);
    }
  }

  /// Inserts segments from a pasted block inline at the cursor position.
  void _insertSegmentsAtCursor(
    DocumentModel document,
    CursorPositionInTextBlock cursor,
    List<TextSegment> pasteSegments,
  ) {
    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final segs = block.segments.value;

    final (before, after) = splitSegmentsAt(segs, flatOffset);

    final newSegs = [...before, ...pasteSegments, ...after];
    final filtered = newSegs.where((s) => s.text.isNotEmpty).toList();
    final normalized = filtered.isEmpty
        ? [const TextSegment(text: '')]
        : filtered;

    block.segments.replaceRange(0, block.segments.length, normalized);

    // Cursor at end of pasted content.
    final pastedLength = pasteSegments.fold<int>(
      0,
      (sum, s) => sum + s.text.length,
    );
    final newCursorFlat = flatOffset + pastedLength;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(newCursorFlat),
    );
  }

  /// Inserts multiple blocks at the cursor position, splitting the current block.
  void _insertBlocksAtCursor(
    DocumentModel document,
    CursorPositionInTextBlock cursor,
    List<TextBlock> pasteBlocks,
  ) {
    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final segs = block.segments.value;

    final (before, after) = splitSegmentsAt(segs, flatOffset);

    // Update current block with: before + first pasted block's segments.
    final firstPasteSegs = pasteBlocks.first.segments.value;
    final currentBlockNewSegs = [...before, ...firstPasteSegs];
    final currentFiltered = currentBlockNewSegs
        .where((s) => s.text.isNotEmpty)
        .toList();
    final currentNormalized = currentFiltered.isEmpty
        ? [const TextSegment(text: '')]
        : currentFiltered;
    block.segments.replaceRange(0, block.segments.length, currentNormalized);

    // Insert middle blocks (index 1 to length-2) after the current block.
    final siblings = block.parent.value is ContainerBlock
        ? (block.parent.value as ContainerBlock).children
        : document.rootBlocks;
    var insertIdx = siblings.value.indexOf(block) + 1;

    for (var i = 1; i < pasteBlocks.length - 1; i++) {
      final middleBlock = pasteBlocks[i];
      middleBlock.parent.value = block.parent.value;
      document.addBlock(middleBlock, insertIdx);
      insertIdx++;
    }

    // Create a new block with: last pasted block's segments + after.
    final lastPasteSegs = pasteBlocks.last.segments.value;
    final afterBlockSegs = [...lastPasteSegs, ...after];
    final afterFiltered = afterBlockSegs
        .where((s) => s.text.isNotEmpty)
        .toList();
    final afterNormalized = afterFiltered.isEmpty
        ? [const TextSegment(text: '')]
        : afterFiltered;

    final newBlock = TextBlock(
      id: _idService.generateId(),
      documentId: document.id,
      parent: ValueNotifier(block.parent.value),
      segments: ListNotifier(data: afterNormalized),
    );
    document.addBlock(newBlock, insertIdx);

    // Cursor at end of last pasted block's segments (before 'after' content).
    final lastPastedLen = lastPasteSegs.fold<int>(
      0,
      (sum, s) => sum + s.text.length,
    );
    document.selection.value = SingleCursorSelectionState(
      cursorPos: newBlock.cursorPosFromFlatOffset(lastPastedLen),
    );
  }

  void _handleSplitTextBlock(SplitTextBlock action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    // 1. Split segments into two halves.
    final (beforeSegments, afterSegments) = splitSegmentsAt(
      block.segments.value,
      action.splitFlatOffset,
    );

    // Normalize: ensure each half has at least one segment.
    final normalizedBefore = beforeSegments.isEmpty
        ? [const TextSegment(text: '')]
        : beforeSegments;
    final normalizedAfter = afterSegments.isEmpty
        ? [const TextSegment(text: '')]
        : afterSegments;

    // 2. Update the current block with the "before" segments.
    block.segments.replaceRange(0, block.segments.length, normalizedBefore);

    // 3. Create a new block with the "after" segments.
    final newBlock = TextBlock(
      id: _idService.generateId(),
      documentId: action.documentId,
      parent: ValueNotifier(block.parent.value),
      segments: ListNotifier(data: normalizedAfter),
    );

    // 4. Insert the new block immediately after the current one.
    final siblings = block.parent.value is ContainerBlock
        ? (block.parent.value as ContainerBlock).children
        : document.rootBlocks;
    final currentIndex = siblings.value.indexOf(block);
    document.addBlock(newBlock, currentIndex + 1);

    // 5. Move cursor to the beginning of the new block.
    document.selection.value = SingleCursorSelectionState(
      cursorPos: CursorPositionInTextBlock(
        blockId: newBlock.id,
        segmentIndex: 0,
        offset: 0,
      ),
    );
  }

  void _handleReplaceText(ReplaceText action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    final segs = block.segments.value;

    // 1. Split at flatStart → (before, fromStart).
    final (before, fromStart) = splitSegmentsAt(segs, action.flatStart);

    // 2. Split fromStart at the replaced range length → (replaced, after).
    final rangeLen = action.flatEnd - action.flatStart;
    final (replaced, after) = splitSegmentsAt(fromStart, rangeLen);

    // 3. Build replacement segment inheriting format from the first segment
    //    of the replaced range.
    final newSegs = <TextSegment>[
      ...before,
      if (action.replacementText.isNotEmpty)
        replaced.isNotEmpty
            ? replaced.first.cloneWithText(action.replacementText)
            : TextSegment(text: action.replacementText),
      ...after,
    ];

    // Remove empty segments but keep at least one.
    final filtered = newSegs.where((s) => s.text.isNotEmpty).toList();
    final normalized = filtered.isEmpty
        ? [const TextSegment(text: '')]
        : filtered;

    block.segments.replaceRange(0, block.segments.length, normalized);

    // 4. Place cursor at end of replacement text.
    final newFlatOffset = action.flatStart + action.replacementText.length;
    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(newFlatOffset),
    );
  }

  /// Splits [segments] at [flatOffset], returning two lists of segments.
  ///
  /// Formatting is preserved: if the split falls in the middle of a segment,
  /// that segment is duplicated into two with the same type and format, each
  /// carrying its respective portion of the text.
  (List<TextSegment>, List<TextSegment>) splitSegmentsAt(
    List<TextSegment> segments,
    int flatOffset,
  ) {
    final before = <TextSegment>[];
    final after = <TextSegment>[];
    int remaining = flatOffset;

    for (final seg in segments) {
      final len = seg.text.length;

      if (remaining <= 0) {
        after.add(seg);
      } else if (remaining >= len) {
        before.add(seg);
        remaining -= len;
      } else {
        before.add(seg.cloneWithText(seg.text.substring(0, remaining)));
        after.add(seg.cloneWithText(seg.text.substring(remaining)));
        remaining = 0;
      }
    }

    return (before, after);
  }
}
