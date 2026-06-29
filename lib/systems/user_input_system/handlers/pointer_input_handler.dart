// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/user_input_system/handlers/ime_input_handler.dart';

class PointerInputHandler {
  late final PageSystem _pageSystem;
  late final ImeInputHandler _ime;

  void init(PageSystem pageSystem, ImeInputHandler ime) {
    _pageSystem = pageSystem;
    _ime = ime;
  }

  void handleTextClick(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    _pageSystem.selection.handleClick(blockId, segmentIndex, offset);
    _ime.syncImeState(pageId);
  }

  void handleShiftClick(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    CursorPositionInTextBlock anchor;
    if (selection is SingleCursorSelectionEntity) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
    } else if (selection is RangeSelectionEntity) {
      final a = selection.anchor;
      if (a is! CursorPositionInTextBlock) return;
      anchor = a;
    } else {
      return;
    }

    _pageSystem.selection.setRangeSelection(
      anchorBlockId: anchor.blockId,
      anchorSegmentIndex: anchor.segmentIndex,
      anchorOffset: anchor.offset,
      extentBlockId: blockId,
      extentSegmentIndex: segmentIndex,
      extentOffset: offset,
    );

    _ime.syncImeState(pageId);
  }

  void handleDragStart(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    _pageSystem.selection.handleClick(blockId, segmentIndex, offset);
  }

  void handleDragUpdate(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    CursorPositionInTextBlock anchor;
    if (selection is SingleCursorSelectionEntity) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
    } else if (selection is RangeSelectionEntity) {
      final a = selection.anchor;
      if (a is! CursorPositionInTextBlock) return;
      anchor = a;
    } else {
      return;
    }

    _pageSystem.selection.setRangeSelection(
      anchorBlockId: anchor.blockId,
      anchorSegmentIndex: anchor.segmentIndex,
      anchorOffset: anchor.offset,
      extentBlockId: blockId,
      extentSegmentIndex: segmentIndex,
      extentOffset: offset,
    );
  }

  void handleDragEnd(String pageId) {
    _ime.syncImeState(pageId);
  }

  void swapSelectionAnchors() {
    _pageSystem.selection.swapSelectionAnchors();
  }
}
