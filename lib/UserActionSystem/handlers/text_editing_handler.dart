// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/utils/segment_utils.dart';

class TextEditingHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final IdService _idService;

  void init(OpenedDocumentsManager documentsManager, IdService idService) {
    _documentsManager = documentsManager;
    _idService = idService;
  }

  void handleInsertText(InsertText action) {
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

  void handleDeleteTextBack(DeleteTextBack action) {
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
      mergeAdjacentBlocks(
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

  void handleDeleteTextForward(DeleteTextForward action) {
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
      mergeAdjacentBlocks(
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
  void mergeAdjacentBlocks({
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

  void handleReplaceText(ReplaceText action) {
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
    final normalized = normalizeSegments(newSegs);
    block.segments.replaceRange(0, block.segments.length, normalized);

    // 4. Place cursor at end of replacement text.
    final newFlatOffset = action.flatStart + action.replacementText.length;
    document.selection.value = SingleCursorSelectionState(
      cursorPos: block.cursorPosFromFlatOffset(newFlatOffset),
    );
  }

  void handleSplitTextBlock(SplitTextBlock action) {
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
}
