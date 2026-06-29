// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/page_system/page_action_dispatcher.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/page_system/segment_utils.dart';

class PageEditingSubsystem {
  final PageSystem _pageSystem;
  final IIdService _idService;
  final PageActionDispatcher _dispatcher;

  PageEditingSubsystem(this._pageSystem, this._idService, this._dispatcher);

  void insertText(int flatOffset, String text) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final insertionPos = block.cursorPosFromFlatOffset(flatOffset);
    final segment = block.segments[insertionPos.segmentIndex];
    final newText = segment.text.replaceRange(
      insertionPos.offset,
      insertionPos.offset,
      text,
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments);
    newSegments[insertionPos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    final newFlatOffset = flatOffset + text.length;
    final newCursorPos = block.cursorPosFromFlatOffset(newFlatOffset);

    page.selection.value = SingleCursorSelectionEntity(cursorPos: newCursorPos);

    _dispatcher.dispatch(
      InsertTextAction(
        blockId: cursor.blockId,
        flatOffset: flatOffset,
        text: text,
      ),
    );
  }

  void deleteTextBack(int flatOffset) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    if (flatOffset <= 0) {
      _mergeWithPreviousBlock(page, block);
      return;
    }

    final deletePos = block.charPosFromFlatOffset(flatOffset - 1);
    if (deletePos == null) return;

    final segment = block.segments[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset,
      deletePos.offset + 1,
      '',
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments);
    newSegments[deletePos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    final newFlatOffset = flatOffset - 1;
    final newCursorPos = block.cursorPosFromFlatOffset(newFlatOffset);

    page.selection.value = SingleCursorSelectionEntity(cursorPos: newCursorPos);

    _dispatcher.dispatch(
      DeleteTextBackAction(blockId: cursor.blockId, flatOffset: flatOffset),
    );
  }

  void deleteTextForward(int flatOffset) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final totalLength = block.computeAllSegmentsText().length;
    if (flatOffset >= totalLength) {
      _mergeWithNextBlock(page, block);
      return;
    }

    final deletePos = block.charPosFromFlatOffset(flatOffset);
    if (deletePos == null) return;

    final segment = block.segments[deletePos.segmentIndex];
    final newText = segment.text.replaceRange(
      deletePos.offset,
      deletePos.offset + 1,
      '',
    );
    final newSegment = segment.cloneWithText(newText);

    final newSegments = List<TextSegment>.from(block.segments);
    newSegments[deletePos.segmentIndex] = newSegment;
    block.segments.replaceRange(0, block.segments.length, newSegments);

    final newCursorPos = block.cursorPosFromFlatOffset(flatOffset);

    page.selection.value = SingleCursorSelectionEntity(cursorPos: newCursorPos);

    _dispatcher.dispatch(
      DeleteTextForwardAction(blockId: cursor.blockId, flatOffset: flatOffset),
    );
  }

  void splitBlock(int splitOffset) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final (beforeSegments, afterSegments) = splitSegmentsAt(
      List.of(block.segments),
      splitOffset,
    );

    final normalizedBefore = beforeSegments.isEmpty
        ? [const TextSegment(text: '')]
        : beforeSegments;
    final normalizedAfter = afterSegments.isEmpty
        ? [const TextSegment(text: '')]
        : afterSegments;

    block.segments.replaceRange(0, block.segments.length, normalizedBefore);

    final newBlock = TextBlockEntity(
      id: _idService.generateId(),
      parentId: block.parentId,
      segments: normalizedAfter,
    );

    final siblings = block.parentId == null
        ? page.rootBlocks
        : (page.getBlockById(block.parentId!)?.children ?? page.rootBlocks);
    final currentIndex = siblings.indexOf(block);
    page.addBlockAt(newBlock, currentIndex + 1);

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: CursorPositionInTextBlock(
        blockId: newBlock.id,
        segmentIndex: 0,
        offset: 0,
      ),
    );

    _dispatcher.dispatch(
      BlockSplitAction(blockId: cursor.blockId, splitOffset: splitOffset),
    );
  }

  void replaceText(int flatStart, int flatEnd, String replacement) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final segs = List.of(block.segments);

    final (before, fromStart) = splitSegmentsAt(segs, flatStart);
    final rangeLen = flatEnd - flatStart;
    final (replaced, after) = splitSegmentsAt(fromStart, rangeLen);

    final newSegs = <TextSegment>[
      ...before,
      if (replacement.isNotEmpty)
        replaced.isNotEmpty
            ? replaced.first.cloneWithText(replacement)
            : TextSegment(text: replacement),
      ...after,
    ];

    final normalized = normalizeSegments(newSegs);
    block.segments.replaceRange(0, block.segments.length, normalized);

    final newFlatOffset = flatStart + replacement.length;
    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: block.cursorPosFromFlatOffset(newFlatOffset),
    );

    _dispatcher.dispatch(
      ReplaceTextAction(
        blockId: cursor.blockId,
        flatStart: flatStart,
        flatEnd: flatEnd,
        replacement: replacement,
      ),
    );
  }

  void deleteSelection() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! RangeSelectionEntity) return;

    final anchor = selection.anchor;
    final extent = selection.extent;
    if (anchor is! CursorPositionInTextBlock ||
        extent is! CursorPositionInTextBlock) {
      return;
    }

    final (first, last) = orderedCursors(page, anchor, extent);
    if (first == null || last == null) return;

    if (first.blockId == last.blockId) {
      _deleteSelectionSingleBlock(page, first, last);
    } else {
      _deleteSelectionMultiBlock(page, first, last);
    }

    _dispatcher.dispatch(DeleteSelectionAction(blockId: first.blockId));
  }

  void _mergeWithPreviousBlock(PageEntity page, TextBlockEntity block) {
    final ids = page.flatBlockIds();
    final idx = ids.indexOf(block.id);
    if (idx <= 0) return;

    final prevBlock = page.getBlockById(ids[idx - 1]);
    if (prevBlock is! TextBlockEntity) return;

    _mergeBlocks(page, prevBlock, block);
  }

  void _mergeWithNextBlock(PageEntity page, TextBlockEntity block) {
    final ids = page.flatBlockIds();
    final idx = ids.indexOf(block.id);
    if (idx == -1 || idx >= ids.length - 1) return;

    final nextBlock = page.getBlockById(ids[idx + 1]);
    if (nextBlock is! TextBlockEntity) return;

    _mergeBlocks(page, block, nextBlock);
  }

  void _mergeBlocks(
    PageEntity page,
    TextBlockEntity leftBlock,
    TextBlockEntity rightBlock,
  ) {
    final leftText = leftBlock.computeAllSegmentsText();
    final leftEmpty = leftText.isEmpty;
    final rightEmpty = rightBlock.computeAllSegmentsText().isEmpty;

    if (leftEmpty) {
      page.removeBlock(leftBlock.id);
      page.selection.value = SingleCursorSelectionEntity(
        cursorPos: rightBlock.cursorPosFromFlatOffset(0),
      );
      return;
    }

    if (rightEmpty) {
      page.removeBlock(rightBlock.id);
      page.selection.value = SingleCursorSelectionEntity(
        cursorPos: leftBlock.cursorPosFromFlatOffset(leftText.length),
      );
      return;
    }

    final joinOffset = leftText.length;
    final mergedSegments = [...leftBlock.segments, ...rightBlock.segments];

    leftBlock.segments.replaceRange(
      0,
      leftBlock.segments.length,
      mergedSegments,
    );
    page.removeBlock(rightBlock.id);

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: leftBlock.cursorPosFromFlatOffset(joinOffset),
    );
  }

  void _deleteSelectionSingleBlock(
    PageEntity page,
    CursorPositionInTextBlock first,
    CursorPositionInTextBlock last,
  ) {
    final block = page.getBlockById(first.blockId);
    if (block is! TextBlockEntity) return;

    final firstFlat = block.flatOffsetFromCursor(
      first.segmentIndex,
      first.offset,
    );
    final lastFlat = block.flatOffsetFromCursor(last.segmentIndex, last.offset);

    if (firstFlat == lastFlat) return;

    final segs = List.of(block.segments);

    final (beforeLast, afterLast) = splitSegmentsAt(segs, lastFlat);
    final (beforeFirst, _) = splitSegmentsAt(beforeLast, firstFlat);

    final newSegs = [...beforeFirst, ...afterLast];
    final normalized = normalizeSegments(newSegs);

    block.segments.replaceRange(0, block.segments.length, normalized);

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: block.cursorPosFromFlatOffset(firstFlat),
    );
  }

  void _deleteSelectionMultiBlock(
    PageEntity page,
    CursorPositionInTextBlock first,
    CursorPositionInTextBlock last,
  ) {
    final firstBlock = page.getBlockById(first.blockId);
    final lastBlock = page.getBlockById(last.blockId);
    if (firstBlock is! TextBlockEntity || lastBlock is! TextBlockEntity) return;

    final firstFlat = firstBlock.flatOffsetFromCursor(
      first.segmentIndex,
      first.offset,
    );
    final lastFlat = lastBlock.flatOffsetFromCursor(
      last.segmentIndex,
      last.offset,
    );

    final (keepBefore, _) = splitSegmentsAt(
      List.of(firstBlock.segments),
      firstFlat,
    );

    final (_, keepAfter) = splitSegmentsAt(
      List.of(lastBlock.segments),
      lastFlat,
    );

    final ids = page.flatBlockIds();
    final firstIdx = ids.indexOf(first.blockId);
    final lastIdx = ids.indexOf(last.blockId);
    for (var i = lastIdx - 1; i > firstIdx; i--) {
      page.removeBlock(ids[i]);
    }

    final mergedSegs = [...keepBefore, ...keepAfter];
    final normalized = normalizeSegments(mergedSegs);

    firstBlock.segments.replaceRange(0, firstBlock.segments.length, normalized);
    page.removeBlock(lastBlock.id);

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: firstBlock.cursorPosFromFlatOffset(firstFlat),
    );
  }
}
