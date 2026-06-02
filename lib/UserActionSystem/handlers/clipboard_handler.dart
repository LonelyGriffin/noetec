// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/MarkdownSystem/markdown_parser.dart';
import 'package:noetec/MarkdownSystem/markdown_serializer.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/utils/segment_utils.dart';
import 'package:noetec/UserActionSystem/handlers/selection_handler.dart';

class ClipboardHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final IdService _idService;
  late final SelectionHandler _selectionHandler;

  void init(
    OpenedDocumentsManager documentsManager,
    IdService idService,
    SelectionHandler selectionHandler,
  ) {
    _documentsManager = documentsManager;
    _idService = idService;
    _selectionHandler = selectionHandler;
  }

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

    final (first, last) = orderedCursors(document, anchor, extent);
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

  void handlePaste(Paste action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    // If there is a range selection, delete it first.
    if (document.selection.value is RangeSelectionState) {
      _selectionHandler.handleDeleteSelection(
        DeleteSelection(documentId: action.documentId),
      );
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
    final normalized = normalizeSegments(newSegs);

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
    final currentNormalized = normalizeSegments(currentBlockNewSegs);
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
    final afterNormalized = normalizeSegments(afterBlockSegs);

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
}
