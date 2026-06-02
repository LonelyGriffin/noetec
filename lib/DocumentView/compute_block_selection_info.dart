// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';

/// Computes what role a specific block plays in the current selection.
///
/// Pure function — takes only data inputs, no widget or model dependencies.
/// This makes it independently testable.
///
/// [blockId] — the block to compute the selection info for.
/// [state] — the current document selection state.
/// [flatBlockIds] — returns all block IDs in document order (depth-first).
/// [selectedBlockIds] — the set of block IDs that are part of the selection range.
BlockSelectionInfo computeBlockSelectionInfo({
  required String blockId,
  required SelectionState state,
  required List<String> Function() flatBlockIds,
  required Set<String> selectedBlockIds,
}) {
  if (state is NoSelectionState) {
    return const BlockNotSelected();
  }

  if (state is SingleCursorSelectionState) {
    final cursorPos = state.cursorPos;

    if (cursorPos is! CursorPositionInTextBlock) {
      return const BlockNotSelected();
    }

    return cursorPos.blockId == blockId
        ? BlockWithCursor(cursorPos: cursorPos)
        : const BlockNotSelected();
  }

  if (state is RangeSelectionState) {
    final anchorCursorPos = state.anchor;
    final extentCursorPos = state.extent;

    // Both anchor and extent are in this block — intra-block range.
    if (anchorCursorPos is CursorPositionInTextBlock &&
        extentCursorPos is CursorPositionInTextBlock &&
        anchorCursorPos.blockId == extentCursorPos.blockId &&
        anchorCursorPos.blockId == blockId) {
      return BlockWithRange(
        anchorCursorPos: anchorCursorPos,
        extentCursorPos: extentCursorPos,
      );
    }

    // For cross-block selection, determine document order of anchor and extent
    // to decide which direction each boundary block should highlight.
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
        // Anchor block: if anchor comes first in doc order, select from anchor to end;
        // otherwise select from start to anchor.
        return anchorIsFirst
            ? BlockSelectedToEnd(cursorPos: anchorCursorPos)
            : BlockSelectedFromStart(cursorPos: anchorCursorPos);
      }

      if (extentIsInThisBlock) {
        // Extent block: if anchor comes first, extent is last → select from start to extent;
        // otherwise extent comes first → select from extent to end.
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
