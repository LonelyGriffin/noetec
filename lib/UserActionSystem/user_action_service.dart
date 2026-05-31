// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/IdService/id_service.dart';
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

  void _handleDeleteTextBack(DeleteTextBack action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    if (action.flatOffset <= 0) return;

    // The character to delete is at flatOffset - 1.
    final deletePos = block.charPosFromFlatOffset(action.flatOffset - 1);
    if (deletePos == null) return;

    final segment = block.segments.value[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset, deletePos.offset + 1, '',
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
    if (action.flatOffset >= totalLength) return;

    // The character to delete is at flatOffset (the one right after the cursor).
    final deletePos = block.charPosFromFlatOffset(action.flatOffset);
    if (deletePos == null) return;

    final segment = block.segments.value[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset, deletePos.offset + 1, '',
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

  void _handleMoveCursor(MoveCursor action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset =
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);
    final totalLength = block.computeAllSegmentsText().length;

    final int newFlatOffset;
    switch (action.direction) {
      case CursorMoveDirection.left:
        newFlatOffset = flatOffset > 0 ? flatOffset - 1 : 0;
      case CursorMoveDirection.right:
        newFlatOffset =
            flatOffset < totalLength ? flatOffset + 1 : totalLength;
    }

    if (newFlatOffset == flatOffset) return;

    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(newFlatOffset),
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
