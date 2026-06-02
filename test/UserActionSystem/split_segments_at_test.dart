// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/UserActionSystem/utils/segment_utils.dart';

void main() {
  // ---------------------------------------------------------------------------
  // splitSegmentsAt
  // ---------------------------------------------------------------------------
  group('splitSegmentsAt', () {
    test('split at start produces empty before, full after', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = splitSegmentsAt(segments, 0);
      expect(before, isEmpty);
      expect(after.length, 2);
      expect(after[0].text, 'Hello');
      expect(after[1].text, ' World');
    });

    test('split at end produces full before, empty after', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = splitSegmentsAt(segments, 11);
      expect(before.length, 2);
      expect(after, isEmpty);
    });

    test('split at segment boundary', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = splitSegmentsAt(segments, 5);
      expect(before.length, 1);
      expect(before[0].text, 'Hello');
      expect(after.length, 1);
      expect(after[0].text, ' World');
    });

    test('split in middle of segment', () {
      final segments = [const TextSegment(text: 'Hello World')];

      final (before, after) = splitSegmentsAt(segments, 5);
      expect(before.length, 1);
      expect(before[0].text, 'Hello');
      expect(after.length, 1);
      expect(after[0].text, ' World');
    });

    test('split preserves FormattedSegment type', () {
      final segments = [
        const FormattedSegment(text: 'BoldText', format: TextFormat.bold),
      ];

      final (before, after) = splitSegmentsAt(segments, 4);
      expect(before[0], isA<FormattedSegment>());
      expect((before[0] as FormattedSegment).format, TextFormat.bold);
      expect(before[0].text, 'Bold');
      expect(after[0], isA<FormattedSegment>());
      expect((after[0] as FormattedSegment).format, TextFormat.bold);
      expect(after[0].text, 'Text');
    });
  });
}
