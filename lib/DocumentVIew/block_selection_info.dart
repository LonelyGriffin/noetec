/// View-layer data classes describing how a text block participates in the current selection.
/// This is not part of the domain model; it's a presentational concern.

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
/// This occurs when:
/// - Selection is collapsed (from == to) in this block, OR
/// - One edge of a range starts/ends in this block (the other edge is in a different block)
class BlockWithCursor extends BlockSelectionInfo {
  final int segmentIndex;
  final int offset;

  const BlockWithCursor({required this.segmentIndex, required this.offset});

  @override
  bool operator ==(Object other) =>
      other is BlockWithCursor &&
      other.segmentIndex == segmentIndex &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(segmentIndex, offset);
}

/// Block contains both cursors of a range (from and to are in the same block).
/// Both cursor positions are needed to render the selection range within the block.
class BlockWithRange extends BlockSelectionInfo {
  final int fromSegmentIndex;
  final int fromOffset;
  final int toSegmentIndex;
  final int toOffset;

  const BlockWithRange({
    required this.fromSegmentIndex,
    required this.fromOffset,
    required this.toSegmentIndex,
    required this.toOffset,
  });

  @override
  bool operator ==(Object other) =>
      other is BlockWithRange &&
      other.fromSegmentIndex == fromSegmentIndex &&
      other.fromOffset == fromOffset &&
      other.toSegmentIndex == toSegmentIndex &&
      other.toOffset == toOffset;

  @override
  int get hashCode =>
      Object.hash(fromSegmentIndex, fromOffset, toSegmentIndex, toOffset);
}
