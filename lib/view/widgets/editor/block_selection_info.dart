// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/selection.dart';

sealed class BlockSelectionInfo {
  const BlockSelectionInfo();
}

class BlockNotSelected extends BlockSelectionInfo {
  const BlockNotSelected();

  @override
  bool operator ==(Object other) => other is BlockNotSelected;

  @override
  int get hashCode => 0;
}

class BlockFullySelected extends BlockSelectionInfo {
  const BlockFullySelected();

  @override
  bool operator ==(Object other) => other is BlockFullySelected;

  @override
  int get hashCode => 1;
}

class BlockWithCursor extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockWithCursor({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockWithCursor && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

class BlockSelectedFromStart extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockSelectedFromStart({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockSelectedFromStart && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

class BlockSelectedToEnd extends BlockSelectionInfo {
  final CursorPositionInTextBlock cursorPos;

  const BlockSelectedToEnd({required this.cursorPos});

  @override
  bool operator ==(Object other) =>
      other is BlockSelectedToEnd && other.cursorPos == cursorPos;

  @override
  int get hashCode => cursorPos.hashCode;
}

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
