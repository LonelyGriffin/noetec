// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/utils/segment_utils.dart';
import 'package:noetec/UserActionSystem/handlers/cursor_handler.dart';

class SelectionHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final CursorHandler _cursorHandler;

  void init(
    OpenedDocumentsManager documentsManager,
    CursorHandler cursorHandler,
  ) {
    _documentsManager = documentsManager;
    _cursorHandler = cursorHandler;
  }

  void handleExtendSelection(ExtendSelection action) {
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
    final newExtent = _cursorHandler.moveCursorPosition(
      document,
      extent,
      action.direction,
    );
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

  void handleSetRangeSelection(SetRangeSelection action) {
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

  void handleSelectAll(SelectAll action) {
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

  void handleSelectWord(SelectWord action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      action.segmentIndex,
      action.offset,
    );

    final (start, end) = block.wordBoundaryAt(flatOffset);

    if (start == end) {
      // Empty block or degenerate case — just place cursor.
      document.selection.value = SingleCursorSelectionState(
        cursorPos: block.cursorPosFromFlatOffset(start),
      );
      return;
    }

    final anchor = block.cursorPosFromFlatOffset(start);
    final extent = block.cursorPosFromFlatOffset(end);

    document.selection.value = RangeSelectionState(
      anchor: anchor,
      extent: extent,
    );
  }

  void handleDeleteSelection(DeleteSelection action) {
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
    final (first, last) = orderedCursors(document, anchor, extent);
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
    final normalized = normalizeSegments(newSegs);

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
    final normalized = normalizeSegments(mergedSegs);

    firstBlock.segments.replaceRange(0, firstBlock.segments.length, normalized);
    document.removeBlock(lastBlock.id);

    // 5. Cursor at the join point.
    document.selection.value = SingleCursorSelectionState(
      cursorPos: firstBlock.cursorPosFromFlatOffset(firstFlat),
    );
  }
}
