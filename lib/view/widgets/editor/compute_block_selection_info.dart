// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/view/widgets/editor/block_selection_info.dart';

BlockSelectionInfo computeBlockSelectionInfo({
  required String blockId,
  required SelectionEntity state,
  required List<String> Function() flatBlockIds,
  required Set<String> selectedBlockIds,
}) {
  if (state is NoSelectionEntity) {
    return const BlockNotSelected();
  }

  if (state is SingleCursorSelectionEntity) {
    final cursorPos = state.cursorPos;

    if (cursorPos is! CursorPositionInTextBlock) {
      return const BlockNotSelected();
    }

    return cursorPos.blockId == blockId
        ? BlockWithCursor(cursorPos: cursorPos)
        : const BlockNotSelected();
  }

  if (state is RangeSelectionEntity) {
    final anchorCursorPos = state.anchor;
    final extentCursorPos = state.extent;

    if (anchorCursorPos is CursorPositionInTextBlock &&
        extentCursorPos is CursorPositionInTextBlock &&
        anchorCursorPos.blockId == extentCursorPos.blockId &&
        anchorCursorPos.blockId == blockId) {
      return BlockWithRange(
        anchorCursorPos: anchorCursorPos,
        extentCursorPos: extentCursorPos,
      );
    }

    final anchorIsInThisBlock =
        anchorCursorPos is CursorPositionInTextBlock &&
        anchorCursorPos.blockId == blockId;
    final extentIsInThisBlock =
        extentCursorPos is CursorPositionInTextBlock &&
        extentCursorPos.blockId == blockId;

    if (anchorIsInThisBlock || extentIsInThisBlock) {
      final blockIds = flatBlockIds();
      final anchorIdx = blockIds.indexOf(anchorCursorPos.blockId);
      final extentIdx = blockIds.indexOf(extentCursorPos.blockId);
      final anchorIsFirst = anchorIdx <= extentIdx;

      if (anchorIsInThisBlock) {
        return anchorIsFirst
            ? BlockSelectedToEnd(cursorPos: anchorCursorPos)
            : BlockSelectedFromStart(cursorPos: anchorCursorPos);
      }

      if (extentIsInThisBlock) {
        return anchorIsFirst
            ? BlockSelectedFromStart(cursorPos: extentCursorPos)
            : BlockSelectedToEnd(cursorPos: extentCursorPos);
      }
    }

    if (selectedBlockIds.contains(blockId)) {
      return const BlockFullySelected();
    }

    return const BlockNotSelected();
  }

  return const BlockNotSelected();
}
