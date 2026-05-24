import 'package:flutter/foundation.dart';

@immutable
sealed class SelectionState {
  const SelectionState();
}

class NoSelectionState extends SelectionState {}

class TextSelectionState extends SelectionState {
  final TextSelectionCursorState from;
  final TextSelectionCursorState to;

  const TextSelectionState({required this.from, required this.to});

  bool get isCollapsed => from == to;
}

@immutable
sealed class SelectionCursorState {
  const SelectionCursorState();

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

class TextSelectionCursorState extends SelectionCursorState {
  final String blockId;
  final int segmentIndex;
  final int offset;

  const TextSelectionCursorState({
    required this.blockId,
    required this.segmentIndex,
    required this.offset,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TextSelectionCursorState &&
        other.blockId == blockId &&
        other.segmentIndex == segmentIndex &&
        other.offset == offset;
  }

  @override
  int get hashCode => blockId.hashCode ^ segmentIndex.hashCode ^ offset.hashCode;
}
