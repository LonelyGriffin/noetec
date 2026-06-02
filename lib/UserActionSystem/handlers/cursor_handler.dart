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

class CursorHandler {
  late final OpenedDocumentsManager _documentsManager;

  void init(OpenedDocumentsManager documentsManager) {
    _documentsManager = documentsManager;
  }

  void handleClickOnTextBlock(ClickOnTextBlock action) {
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

  void handleSetCursorPosition(SetCursorPosition action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(action.flatOffset),
    );
  }

  void handleMoveCursor(MoveCursor action) {
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
      final (first, last) = orderedCursors(document, anchor, extent);
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

  /// Moves a cursor position by one character in [direction], crossing block
  /// boundaries when needed. Returns `null` if already at the document boundary.
  CursorPositionInTextBlock? moveCursorPosition(
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
}
