// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
sealed class SelectionState {
  const SelectionState();
}

@immutable
class NoSelectionState extends SelectionState {
  const NoSelectionState();
}

@immutable
class RangeSelectionState extends SelectionState {
  final CursorPositionInDocument from;
  final CursorPositionInDocument to;

  const RangeSelectionState({required this.from, required this.to});
}

@immutable
class SingleCursorSelectionState extends SelectionState {
  final CursorPositionInDocument cursorPos;

  const SingleCursorSelectionState({required this.cursorPos});
}

@immutable
sealed class CursorPositionInDocument {
  final String blockId;
  const CursorPositionInDocument({required this.blockId,});

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

@immutable
class CursorPositionInTextBlock extends CursorPositionInDocument {
  final int segmentIndex;
  final int offset;

  const CursorPositionInTextBlock({
    required super.blockId,
    required this.segmentIndex,
    required this.offset,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CursorPositionInTextBlock &&
        other.blockId == blockId &&
        other.segmentIndex == segmentIndex &&
        other.offset == offset;
  }

  @override
  int get hashCode => blockId.hashCode ^ segmentIndex.hashCode ^ offset.hashCode;
}
