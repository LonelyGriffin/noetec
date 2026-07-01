// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/view/widgets/editor/block_selection_info.dart';
import 'package:noetec/view/widgets/editor/compute_block_selection_info.dart';

void main() {
  group('computeBlockSelectionInfo —', () {
    const blockA = 'block-a';
    const blockB = 'block-b';
    const blockC = 'block-c';

    CursorPositionInTextBlock cursor(
      String blockId, {
      int seg = 0,
      int off = 0,
    }) => CursorPositionInTextBlock(
      blockId: blockId,
      segmentIndex: seg,
      offset: off,
    );

    List<String> flatIds() => [blockA, blockB, blockC];

    test('returns BlockNotSelected for NoSelectionEntity', () {
      final result = computeBlockSelectionInfo(
        blockId: blockA,
        state: const NoSelectionEntity(),
        flatBlockIds: flatIds,
        selectedBlockIds: {},
      );

      expect(result, isA<BlockNotSelected>());
    });

    test('returns BlockWithCursor when cursor is in the block', () {
      final pos = cursor(blockA, off: 5);
      final result = computeBlockSelectionInfo(
        blockId: blockA,
        state: SingleCursorSelectionEntity(cursorPos: pos),
        flatBlockIds: flatIds,
        selectedBlockIds: {},
      );

      expect(result, isA<BlockWithCursor>());
      expect((result as BlockWithCursor).cursorPos, pos);
    });

    test('returns BlockNotSelected when cursor is in different block', () {
      final result = computeBlockSelectionInfo(
        blockId: blockA,
        state: SingleCursorSelectionEntity(cursorPos: cursor(blockB)),
        flatBlockIds: flatIds,
        selectedBlockIds: {},
      );

      expect(result, isA<BlockNotSelected>());
    });

    test('returns BlockWithRange for intra-block range selection', () {
      final anchor = cursor(blockA, off: 2);
      final extent = cursor(blockA, off: 8);
      final result = computeBlockSelectionInfo(
        blockId: blockA,
        state: RangeSelectionEntity(anchor: anchor, extent: extent),
        flatBlockIds: flatIds,
        selectedBlockIds: {},
      );

      expect(result, isA<BlockWithRange>());
    });

    test(
      'returns BlockFullySelected for middle block in cross-block selection',
      () {
        final anchor = cursor(blockA, off: 3);
        final extent = cursor(blockC, off: 5);
        final result = computeBlockSelectionInfo(
          blockId: blockB,
          state: RangeSelectionEntity(anchor: anchor, extent: extent),
          flatBlockIds: flatIds,
          selectedBlockIds: {blockB},
        );

        expect(result, isA<BlockFullySelected>());
      },
    );

    test('returns BlockNotSelected for block outside selection range', () {
      final anchor = cursor(blockA, off: 3);
      final extent = cursor(blockB, off: 5);
      final result = computeBlockSelectionInfo(
        blockId: blockC,
        state: RangeSelectionEntity(anchor: anchor, extent: extent),
        flatBlockIds: flatIds,
        selectedBlockIds: {},
      );

      expect(result, isA<BlockNotSelected>());
    });
  });
}
