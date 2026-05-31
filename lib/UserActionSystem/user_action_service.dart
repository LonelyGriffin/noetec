// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';

class UserActionService {
  final OpenedDocumentsManager _documentsManager;

  UserActionService(this._documentsManager);

  void handleAction(UserAction action) {
    switch (action) {
      case InsertText():
        _handleInsertText(action);
      case ClickOnTextBlock():
        _handleClickOnTextBlock(action);
      case SplitTextBlock():
        _handleSplitTextBlock(action);
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
      insertionPos.offset, insertionPos.offset, action.text,
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

  void _handleSplitTextBlock(SplitTextBlock action) {
    // TODO: implement block splitting
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
