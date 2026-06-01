// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';
import 'package:noetec/DocumentView/compute_block_selection_info.dart';

void main() {
  // Shared block order for cross-block tests: block-1, block-2, block-3
  const blockOrder = ['block-1', 'block-2', 'block-3'];

  /// Helper: calls [computeBlockSelectionInfo] with the standard three-block
  /// document layout and a pre-computed [selectedBlockIds] set.
  BlockSelectionInfo compute({
    required String blockId,
    required SelectionState state,
    List<String> flatBlockIds = blockOrder,
    Set<String> selectedBlockIds = const {},
  }) {
    return computeBlockSelectionInfo(
      blockId: blockId,
      state: state,
      flatBlockIds: () => flatBlockIds,
      selectedBlockIds: selectedBlockIds,
    );
  }

  // ---------------------------------------------------------------------------
  // NoSelectionState
  // ---------------------------------------------------------------------------
  group('NoSelectionState', () {
    test('returns BlockNotSelected for any block', () {
      final result = compute(
        blockId: 'block-1',
        state: const NoSelectionState(),
      );

      expect(result, isA<BlockNotSelected>());
    });
  });

  // ---------------------------------------------------------------------------
  // SingleCursorSelectionState
  // ---------------------------------------------------------------------------
  group('SingleCursorSelectionState', () {
    test('returns BlockWithCursor when cursor is in this block', () {
      const cursor = CursorPositionInTextBlock(
        blockId: 'block-1',
        segmentIndex: 0,
        offset: 3,
      );

      final result = compute(
        blockId: 'block-1',
        state: const SingleCursorSelectionState(cursorPos: cursor),
      );

      expect(result, isA<BlockWithCursor>());
      expect((result as BlockWithCursor).cursorPos, cursor);
    });

    test('returns BlockNotSelected when cursor is in another block', () {
      const cursor = CursorPositionInTextBlock(
        blockId: 'block-2',
        segmentIndex: 0,
        offset: 3,
      );

      final result = compute(
        blockId: 'block-1',
        state: const SingleCursorSelectionState(cursorPos: cursor),
      );

      expect(result, isA<BlockNotSelected>());
    });
  });

  // ---------------------------------------------------------------------------
  // RangeSelectionState — same block
  // ---------------------------------------------------------------------------
  group('RangeSelectionState - same block', () {
    test(
      'returns BlockWithRange when both anchor and extent are in this block',
      () {
        const anchor = CursorPositionInTextBlock(
          blockId: 'block-1',
          segmentIndex: 0,
          offset: 1,
        );
        const extent = CursorPositionInTextBlock(
          blockId: 'block-1',
          segmentIndex: 0,
          offset: 5,
        );

        final result = compute(
          blockId: 'block-1',
          state: const RangeSelectionState(anchor: anchor, extent: extent),
        );

        expect(result, isA<BlockWithRange>());
        final range = result as BlockWithRange;
        expect(range.anchorCursorPos, anchor);
        expect(range.extentCursorPos, extent);
      },
    );

    test(
      'returns BlockNotSelected for other blocks when range is within one block',
      () {
        const anchor = CursorPositionInTextBlock(
          blockId: 'block-1',
          segmentIndex: 0,
          offset: 1,
        );
        const extent = CursorPositionInTextBlock(
          blockId: 'block-1',
          segmentIndex: 0,
          offset: 5,
        );

        final result = compute(
          blockId: 'block-2',
          state: const RangeSelectionState(anchor: anchor, extent: extent),
        );

        expect(result, isA<BlockNotSelected>());
      },
    );
  });

  // ---------------------------------------------------------------------------
  // RangeSelectionState — cross-block forward (anchor above extent)
  // ---------------------------------------------------------------------------
  group('RangeSelectionState - cross-block forward (anchor above extent)', () {
    // Selection: anchor in block-1, extent in block-3
    // Document order: block-1, block-2, block-3
    // anchor is FIRST in doc order.
    const anchor = CursorPositionInTextBlock(
      blockId: 'block-1',
      segmentIndex: 0,
      offset: 3,
    );
    const extent = CursorPositionInTextBlock(
      blockId: 'block-3',
      segmentIndex: 0,
      offset: 2,
    );
    const state = RangeSelectionState(anchor: anchor, extent: extent);
    const selected = {'block-1', 'block-2', 'block-3'};

    test('anchor block gets BlockSelectedToEnd', () {
      final result = compute(
        blockId: 'block-1',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedToEnd>());
      expect((result as BlockSelectedToEnd).cursorPos, anchor);
    });

    test('extent block gets BlockSelectedFromStart', () {
      final result = compute(
        blockId: 'block-3',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedFromStart>());
      expect((result as BlockSelectedFromStart).cursorPos, extent);
    });

    test('middle block gets BlockFullySelected', () {
      final result = compute(
        blockId: 'block-2',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockFullySelected>());
    });
  });

  // ---------------------------------------------------------------------------
  // RangeSelectionState — cross-block backward (anchor below extent)
  // ---------------------------------------------------------------------------
  group('RangeSelectionState - cross-block backward (anchor below extent)', () {
    // Selection: anchor in block-3, extent in block-1
    // Document order: block-1, block-2, block-3
    // anchor is LAST in doc order — user selected upward.
    const anchor = CursorPositionInTextBlock(
      blockId: 'block-3',
      segmentIndex: 0,
      offset: 4,
    );
    const extent = CursorPositionInTextBlock(
      blockId: 'block-1',
      segmentIndex: 0,
      offset: 2,
    );
    const state = RangeSelectionState(anchor: anchor, extent: extent);
    const selected = {'block-1', 'block-2', 'block-3'};

    test('anchor block (lower) gets BlockSelectedFromStart', () {
      final result = compute(
        blockId: 'block-3',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedFromStart>());
      expect((result as BlockSelectedFromStart).cursorPos, anchor);
    });

    test('extent block (upper) gets BlockSelectedToEnd', () {
      final result = compute(
        blockId: 'block-1',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedToEnd>());
      expect((result as BlockSelectedToEnd).cursorPos, extent);
    });

    test('middle block gets BlockFullySelected', () {
      final result = compute(
        blockId: 'block-2',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockFullySelected>());
    });
  });

  // ---------------------------------------------------------------------------
  // RangeSelectionState — unrelated block
  // ---------------------------------------------------------------------------
  group('RangeSelectionState - unrelated block', () {
    test('block outside selection range gets BlockNotSelected', () {
      const anchor = CursorPositionInTextBlock(
        blockId: 'block-1',
        segmentIndex: 0,
        offset: 0,
      );
      const extent = CursorPositionInTextBlock(
        blockId: 'block-2',
        segmentIndex: 0,
        offset: 5,
      );

      final result = compute(
        blockId: 'block-3',
        state: const RangeSelectionState(anchor: anchor, extent: extent),
        selectedBlockIds: const {'block-1', 'block-2'},
      );

      expect(result, isA<BlockNotSelected>());
    });
  });

  // ---------------------------------------------------------------------------
  // RangeSelectionState — adjacent blocks (two-block selection)
  // ---------------------------------------------------------------------------
  group('RangeSelectionState - adjacent blocks forward', () {
    const anchor = CursorPositionInTextBlock(
      blockId: 'block-1',
      segmentIndex: 0,
      offset: 5,
    );
    const extent = CursorPositionInTextBlock(
      blockId: 'block-2',
      segmentIndex: 0,
      offset: 3,
    );
    const state = RangeSelectionState(anchor: anchor, extent: extent);
    const selected = {'block-1', 'block-2'};

    test('anchor block gets BlockSelectedToEnd', () {
      final result = compute(
        blockId: 'block-1',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedToEnd>());
    });

    test('extent block gets BlockSelectedFromStart', () {
      final result = compute(
        blockId: 'block-2',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedFromStart>());
    });
  });

  group('RangeSelectionState - adjacent blocks backward', () {
    const anchor = CursorPositionInTextBlock(
      blockId: 'block-2',
      segmentIndex: 0,
      offset: 3,
    );
    const extent = CursorPositionInTextBlock(
      blockId: 'block-1',
      segmentIndex: 0,
      offset: 5,
    );
    const state = RangeSelectionState(anchor: anchor, extent: extent);
    const selected = {'block-1', 'block-2'};

    test('anchor block (lower) gets BlockSelectedFromStart', () {
      final result = compute(
        blockId: 'block-2',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedFromStart>());
    });

    test('extent block (upper) gets BlockSelectedToEnd', () {
      final result = compute(
        blockId: 'block-1',
        state: state,
        selectedBlockIds: selected,
      );

      expect(result, isA<BlockSelectedToEnd>());
    });
  });
}
