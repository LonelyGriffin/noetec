// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/page_system/segment_utils.dart';

class PageSelectionSubsystem {
  final PageSystem _pageSystem;

  PageSelectionSubsystem(this._pageSystem);

  void moveCursor(CursorMoveDirection direction) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    if (selection is RangeSelectionEntity) {
      final anchor = selection.anchor;
      final extent = selection.extent;
      if (anchor is! CursorPositionInTextBlock ||
          extent is! CursorPositionInTextBlock) {
        return;
      }

      final (first, last) = orderedCursors(page, anchor, extent);
      if (first == null || last == null) return;

      switch (direction) {
        case CursorMoveDirection.left:
          page.selection.value = SingleCursorSelectionEntity(cursorPos: first);
        case CursorMoveDirection.right:
          page.selection.value = SingleCursorSelectionEntity(cursorPos: last);
      }
      return;
    }

    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final totalLength = block.computeAllSegmentsText().length;

    switch (direction) {
      case CursorMoveDirection.left:
        if (flatOffset > 0) {
          page.selection.value = SingleCursorSelectionEntity(
            cursorPos: block.cursorPosFromFlatOffset(flatOffset - 1),
          );
        } else {
          _moveToPreviousBlock(page, cursor.blockId);
        }

      case CursorMoveDirection.right:
        if (flatOffset < totalLength) {
          page.selection.value = SingleCursorSelectionEntity(
            cursorPos: block.cursorPosFromFlatOffset(flatOffset + 1),
          );
        } else {
          _moveToNextBlock(page, cursor.blockId);
        }
    }
  }

  void extendSelection(CursorMoveDirection direction) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    CursorPositionInTextBlock anchor;
    CursorPositionInTextBlock extent;

    if (selection is SingleCursorSelectionEntity) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
      extent = cursor;
    } else if (selection is RangeSelectionEntity) {
      if (selection.anchor is! CursorPositionInTextBlock ||
          selection.extent is! CursorPositionInTextBlock) {
        return;
      }
      anchor = selection.anchor as CursorPositionInTextBlock;
      extent = selection.extent as CursorPositionInTextBlock;
    } else {
      return;
    }

    final newExtent = _moveCursorPosition(page, extent, direction);
    if (newExtent == null) return;

    if (anchor == newExtent) {
      page.selection.value = SingleCursorSelectionEntity(cursorPos: anchor);
    } else {
      page.selection.value = RangeSelectionEntity(
        anchor: anchor,
        extent: newExtent,
      );
    }
  }

  void setRangeSelection({
    required String anchorBlockId,
    required int anchorSegmentIndex,
    required int anchorOffset,
    required String extentBlockId,
    required int extentSegmentIndex,
    required int extentOffset,
  }) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final anchorPos = CursorPositionInTextBlock(
      blockId: anchorBlockId,
      segmentIndex: anchorSegmentIndex,
      offset: anchorOffset,
    );
    final extentPos = CursorPositionInTextBlock(
      blockId: extentBlockId,
      segmentIndex: extentSegmentIndex,
      offset: extentOffset,
    );

    if (anchorPos == extentPos) {
      page.selection.value = SingleCursorSelectionEntity(cursorPos: anchorPos);
    } else {
      page.selection.value = RangeSelectionEntity(
        anchor: anchorPos,
        extent: extentPos,
      );
    }
  }

  void selectAll() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final ids = page.flatBlockIds();
    if (ids.isEmpty) return;

    final firstBlock = page.getBlockById(ids.first);
    final lastBlock = page.getBlockById(ids.last);
    if (firstBlock is! TextBlockEntity || lastBlock is! TextBlockEntity) return;

    final anchor = firstBlock.cursorPosFromFlatOffset(0);
    final lastText = lastBlock.computeAllSegmentsText();
    final extent = lastBlock.cursorPosFromFlatOffset(lastText.length);

    if (anchor == extent) {
      page.selection.value = SingleCursorSelectionEntity(cursorPos: anchor);
    } else {
      page.selection.value = RangeSelectionEntity(
        anchor: anchor,
        extent: extent,
      );
    }
  }

  void setCursorPosition(int flatOffset) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: block.cursorPosFromFlatOffset(flatOffset),
    );
  }

  void handleClick(String blockId, int segmentIndex, int offset) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: CursorPositionInTextBlock(
        blockId: blockId,
        segmentIndex: segmentIndex,
        offset: offset,
      ),
    );
  }

  void swapSelectionAnchors() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;
    if (selection is! RangeSelectionEntity) return;

    page.selection.value = RangeSelectionEntity(
      anchor: selection.extent,
      extent: selection.anchor,
    );
  }

  CursorPositionInTextBlock? moveCursorPosition(
    PageEntity page,
    CursorPositionInTextBlock cursor,
    CursorMoveDirection direction,
  ) {
    return _moveCursorPosition(page, cursor, direction);
  }

  CursorPositionInTextBlock? _moveCursorPosition(
    PageEntity page,
    CursorPositionInTextBlock cursor,
    CursorMoveDirection direction,
  ) {
    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return null;

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
        final ids = page.flatBlockIds();
        final idx = ids.indexOf(cursor.blockId);
        if (idx <= 0) return null;
        final prevBlock = page.getBlockById(ids[idx - 1]);
        if (prevBlock is! TextBlockEntity) return null;
        return prevBlock.cursorPosFromFlatOffset(
          prevBlock.computeAllSegmentsText().length,
        );

      case CursorMoveDirection.right:
        if (flatOffset < totalLength) {
          return block.cursorPosFromFlatOffset(flatOffset + 1);
        }
        final ids = page.flatBlockIds();
        final idx = ids.indexOf(cursor.blockId);
        if (idx == -1 || idx >= ids.length - 1) return null;
        final nextBlock = page.getBlockById(ids[idx + 1]);
        if (nextBlock is! TextBlockEntity) return null;
        return nextBlock.cursorPosFromFlatOffset(0);
    }
  }

  void _moveToPreviousBlock(PageEntity page, String currentBlockId) {
    final ids = page.flatBlockIds();
    final idx = ids.indexOf(currentBlockId);
    if (idx <= 0) return;

    final prevBlock = page.getBlockById(ids[idx - 1]);
    if (prevBlock is! TextBlockEntity) return;

    final endOffset = prevBlock.computeAllSegmentsText().length;
    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: prevBlock.cursorPosFromFlatOffset(endOffset),
    );
  }

  void _moveToNextBlock(PageEntity page, String currentBlockId) {
    final ids = page.flatBlockIds();
    final idx = ids.indexOf(currentBlockId);
    if (idx == -1 || idx >= ids.length - 1) return;

    final nextBlock = page.getBlockById(ids[idx + 1]);
    if (nextBlock is! TextBlockEntity) return;

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: nextBlock.cursorPosFromFlatOffset(0),
    );
  }
}
