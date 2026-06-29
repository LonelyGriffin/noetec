// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';

void main() {
  group('TextBlockEntity —', () {
    group('computeAllSegmentsText —', () {
      test('returns empty string for default block', () {
        final block = TextBlockEntity(id: 'b1');
        expect(block.computeAllSegmentsText(), '');
      });

      test('concatenates all segment texts', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'Hello '),
            const FormattedSegment(text: 'bold', format: TextFormat.bold),
            const TextSegment(text: ' world'),
          ],
        );
        expect(block.computeAllSegmentsText(), 'Hello bold world');
      });
    });

    group('flatOffsetFromCursor —', () {
      test('returns offset within first segment', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        expect(block.flatOffsetFromCursor(0, 2), 2);
      });

      test('returns correct offset for second segment', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        expect(block.flatOffsetFromCursor(1, 1), 4);
      });

      test('returns zero for start of first segment', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'abc')],
        );
        expect(block.flatOffsetFromCursor(0, 0), 0);
      });
    });

    group('cursorPosFromFlatOffset —', () {
      test('returns position in first segment for small offset', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        final pos = block.cursorPosFromFlatOffset(2);
        expect(pos.blockId, 'b1');
        expect(pos.segmentIndex, 0);
        expect(pos.offset, 2);
      });

      test('returns position in second segment for larger offset', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        final pos = block.cursorPosFromFlatOffset(4);
        expect(pos.segmentIndex, 1);
        expect(pos.offset, 1);
      });

      test('returns end of last segment for total length', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        final pos = block.cursorPosFromFlatOffset(6);
        expect(pos.segmentIndex, 1);
        expect(pos.offset, 3);
      });

      test('handles single empty segment', () {
        final block = TextBlockEntity(id: 'b1');
        final pos = block.cursorPosFromFlatOffset(0);
        expect(pos.segmentIndex, 0);
        expect(pos.offset, 0);
      });
    });

    group('charPosFromFlatOffset —', () {
      test('returns position for valid offset', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const TextSegment(text: 'abc'),
            const TextSegment(text: 'def'),
          ],
        );
        final pos = block.charPosFromFlatOffset(4);
        expect(pos, isNotNull);
        expect(pos!.segmentIndex, 1);
        expect(pos.offset, 1);
      });

      test('returns null for offset at total length', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'abc')],
        );
        expect(block.charPosFromFlatOffset(3), isNull);
      });
    });

    group('wordBoundaryAt —', () {
      test('returns word boundaries for position inside word', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'hello world')],
        );
        final (start, end) = block.wordBoundaryAt(2);
        expect(start, 0);
        expect(end, 5);
      });

      test('returns same position for non-word character', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'hello world')],
        );
        final (start, end) = block.wordBoundaryAt(5);
        expect(start, 5);
        expect(end, 5);
      });

      test('returns (0, 0) for empty block', () {
        final block = TextBlockEntity(id: 'b1');
        final (start, end) = block.wordBoundaryAt(0);
        expect(start, 0);
        expect(end, 0);
      });
    });
  });
}
