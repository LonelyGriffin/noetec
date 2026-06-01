// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// View-layer data classes describing how a text block participates in the current selection.

import 'package:noetec/DocumentSystem/selection_state.dart';

/// Describes the role of a text block in the current text selection.
sealed class BlockSelectionInfo {
  const BlockSelectionInfo();
}

/// Block is not involved in the current selection.
class BlockNotSelected extends BlockSelectionInfo {
  const BlockNotSelected();

  @override
  bool operator ==(Object other) => other is BlockNotSelected;

  @override
  int get hashCode => 0;
}

/// Block is fully selected (both from and to cursors are in other blocks, this block is between them).
class BlockFullySelected extends BlockSelectionInfo {
  const BlockFullySelected();

  @override
  bool operator ==(Object other) => other is BlockFullySelected;

  @override
  int get hashCode => 1;
}

/// Block contains exactly one cursor.
class BlockWithCursor extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockWithCursor({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockWithCursor && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block is selected from the beginning of the block to the cursor position.
/// Used for the block that comes last in document order during a cross-block selection.
class BlockSelectedFromStart extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockSelectedFromStart({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockSelectedFromStart && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block is selected from the cursor position to the end of the block.
/// Used for the block that comes first in document order during a cross-block selection.
class BlockSelectedToEnd extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockSelectedToEnd({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockSelectedToEnd && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block contains both cursors of a range (anchor and extent are in the same block).
class BlockWithRange extends BlockSelectionInfo {
  final CursorPositionInTextBlock anchorCursorPos;
  final CursorPositionInTextBlock extentCursorPos;

  const BlockWithRange({
    required this.anchorCursorPos,
    required this.extentCursorPos,
  });

  @override
  bool operator ==(Object other) =>
      other is BlockWithRange &&
      other.anchorCursorPos == anchorCursorPos &&
      other.extentCursorPos == extentCursorPos;

  @override
  int get hashCode => Object.hash(anchorCursorPos, extentCursorPos);
}
