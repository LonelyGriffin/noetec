// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';

import '../helpers/test_document_factory.dart';

void main() {
  // ---------------------------------------------------------------------------
  // TextBlock.cursorPosFromFlatOffset
  // ---------------------------------------------------------------------------
  group('TextBlock.cursorPosFromFlatOffset', () {
    test('offset 0 in single-segment block returns (0, 0)', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'abc');
      final block = doc.getBlockById(blockId) as TextBlock;

      final pos = block.cursorPosFromFlatOffset(0);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 0);
    });

    test('offset at end of single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'abc');
      final block = doc.getBlockById(blockId) as TextBlock;

      final pos = block.cursorPosFromFlatOffset(3);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 3);
    });

    test('offset in middle of single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'abcdef');
      final block = doc.getBlockById(blockId) as TextBlock;

      final pos = block.cursorPosFromFlatOffset(3);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 3);
    });

    test('offset beyond end is clamped to last segment end', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'abc');
      final block = doc.getBlockById(blockId) as TextBlock;

      final pos = block.cursorPosFromFlatOffset(100);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 3);
    });

    test('multi-segment: offset at boundary lands in earlier segment', () {
      // "Hello " (6) + "bold" (4) + " world" (6)
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      // Offset 6 is end of segment 0 — should remain in segment 0
      final pos = block.cursorPosFromFlatOffset(6);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 6);
    });

    test('multi-segment: offset inside second segment', () {
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      // Offset 8 = "Hello " (6) + 2 into "bold"
      final pos = block.cursorPosFromFlatOffset(8);
      expect(pos.segmentIndex, 1);
      expect(pos.offset, 2);
    });

    test('multi-segment: offset at very end', () {
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      // Total = 6 + 4 + 6 = 16
      final pos = block.cursorPosFromFlatOffset(16);
      expect(pos.segmentIndex, 2);
      expect(pos.offset, 6);
    });

    test('empty block returns (0, 0)', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      final block = doc.getBlockById(blockId) as TextBlock;

      final pos = block.cursorPosFromFlatOffset(0);
      expect(pos.segmentIndex, 0);
      expect(pos.offset, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // TextBlock.flatOffsetFromCursor
  // ---------------------------------------------------------------------------
  group('TextBlock.flatOffsetFromCursor', () {
    test('single segment: (0, 3) -> 3', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'abcdef');
      final block = doc.getBlockById(blockId) as TextBlock;

      expect(block.flatOffsetFromCursor(0, 3), 3);
    });

    test('multi-segment: (1, 2) -> 8', () {
      // "Hello " (6) + "bold" (4) + " world" (6)
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      // Segment 1, offset 2 => 6 + 2 = 8
      expect(block.flatOffsetFromCursor(1, 2), 8);
    });

    test('multi-segment: (2, 0) -> 10', () {
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      // Segment 2, offset 0 => 6 + 4 + 0 = 10
      expect(block.flatOffsetFromCursor(2, 0), 10);
    });
  });

  // ---------------------------------------------------------------------------
  // Round-trip: flatOffset -> cursorPos -> flatOffset
  // ---------------------------------------------------------------------------
  group('cursorPosFromFlatOffset / flatOffsetFromCursor round-trip', () {
    test('every valid offset in multi-segment block round-trips correctly', () {
      final (doc, blockId) = createMultiSegmentDocument();
      final block = doc.getBlockById(blockId) as TextBlock;

      final totalLength = block.computeAllSegmentsText().length; // 16
      for (var flat = 0; flat <= totalLength; flat++) {
        final pos = block.cursorPosFromFlatOffset(flat);
        final roundTripped = block.flatOffsetFromCursor(pos.segmentIndex, pos.offset);
        expect(roundTripped, flat, reason: 'Round-trip failed for flat offset $flat');
      }
    });
  });
}
