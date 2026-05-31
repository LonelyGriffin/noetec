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
      other is BlockWithCursor &&
      other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block selected from start to cursor
/// So block contains last (to) cursor of selection range
class BlockWithToCursor extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockWithToCursor({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockWithToCursor &&
      other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block selected from cursor to end
/// So block contains first (from) cursor of selection range
class BlockWithFromCursor extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockWithFromCursor({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockWithFromCursor &&
      other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

/// Block contains both cursors of a range (from and to are in the same block).
class BlockWithRange extends BlockSelectionInfo {
  final CursorPositionInTextBlock fromCursorPos;
  final CursorPositionInTextBlock toCursorPos;

  const BlockWithRange({
    required this.fromCursorPos,
    required this.toCursorPos,
  });

  @override
  bool operator ==(Object other) =>
      other is BlockWithRange &&
      other.fromCursorPos == fromCursorPos &&
      other.toCursorPos == toCursorPos;

  @override
  int get hashCode =>
      Object.hash(fromCursorPos, toCursorPos);
}
