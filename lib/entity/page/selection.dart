// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

enum CursorMoveDirection { left, right }

@immutable
abstract class SelectionEntity {
  const SelectionEntity();
}

@immutable
class NoSelectionEntity extends SelectionEntity {
  const NoSelectionEntity();
}

@immutable
class RangeSelectionEntity extends SelectionEntity {
  final CursorPositionInDocument anchor;
  final CursorPositionInDocument extent;

  const RangeSelectionEntity({required this.anchor, required this.extent});
}

@immutable
class SingleCursorSelectionEntity extends SelectionEntity {
  final CursorPositionInDocument cursorPos;

  const SingleCursorSelectionEntity({required this.cursorPos});
}

@immutable
sealed class CursorPositionInDocument {
  final String blockId;
  const CursorPositionInDocument({required this.blockId});

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
  int get hashCode =>
      blockId.hashCode ^ segmentIndex.hashCode ^ offset.hashCode;
}
