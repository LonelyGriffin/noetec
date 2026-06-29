// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';

class _FakeIdService implements IIdService {
  int _counter = 0;
  @override
  String generateId() => 'id-${_counter++}';
}

void main() {
  late MarkdownSystem markdownSystem;

  setUp(() {
    markdownSystem = MarkdownSystem(_FakeIdService());
  });

  group('MarkdownSystem —', () {
    group('parseMarkdown —', () {
      test('parses plain paragraph into single block', () {
        final blocks = markdownSystem.parseMarkdown('Hello world');
        expect(blocks.length, 1);
        expect(blocks.first.computeAllSegmentsText(), 'Hello world');
      });

      test('parses bold text into FormattedSegment', () {
        final blocks = markdownSystem.parseMarkdown('**bold text**');
        expect(blocks.length, 1);
        final segments = blocks.first.segments;
        expect(segments.length, 1);
        expect(segments.first, isA<FormattedSegment>());
        final formatted = segments.first as FormattedSegment;
        expect(formatted.text, 'bold text');
        expect(formatted.format.has(TextFormat.bold), isTrue);
      });

      test('parses italic text into FormattedSegment', () {
        final blocks = markdownSystem.parseMarkdown('*italic text*');
        expect(blocks.length, 1);
        final segments = blocks.first.segments;
        expect(segments.first, isA<FormattedSegment>());
        final formatted = segments.first as FormattedSegment;
        expect(formatted.format.has(TextFormat.italic), isTrue);
      });

      test('parses link into LinkSegment', () {
        final blocks = markdownSystem.parseMarkdown(
          '[click](https://example.com)',
        );
        expect(blocks.length, 1);
        final segments = blocks.first.segments;
        expect(segments.first, isA<LinkSegment>());
        final link = segments.first as LinkSegment;
        expect(link.text, 'click');
        expect(link.url, 'https://example.com');
      });

      test('returns at least one block for empty input', () {
        final blocks = markdownSystem.parseMarkdown('');
        expect(blocks.length, 1);
        expect(blocks.first.computeAllSegmentsText(), '');
      });

      test('parses fenced directive block preserving id', () {
        const md = '::: {#my-block}\nHello world\n:::';
        final blocks = markdownSystem.parseMarkdown(md);
        expect(blocks.length, 1);
        expect(blocks.first.id, 'my-block');
        expect(blocks.first.computeAllSegmentsText(), 'Hello world');
      });
    });

    group('serializeBlocks —', () {
      test('serializes single block with fenced directive', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'Hello world')],
        );
        final md = markdownSystem.serializeBlocks([block]);
        expect(md, contains('::: {#b1}'));
        expect(md, contains('Hello world'));
        expect(md, contains(':::'));
      });

      test('serializes bold formatted segment', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const FormattedSegment(text: 'bold', format: TextFormat.bold),
          ],
        );
        final md = markdownSystem.serializeBlocks([block]);
        expect(md, contains('**bold**'));
      });

      test('serializes link segment', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [
            const LinkSegment(text: 'click', url: 'https://example.com'),
          ],
        );
        final md = markdownSystem.serializeBlocks([block]);
        expect(md, contains('[click](https://example.com)'));
      });

      test('serializes with range', () {
        final block = TextBlockEntity(
          id: 'b1',
          segments: [const TextSegment(text: 'hello world')],
        );
        final md = markdownSystem.serializeBlocks([block], ranges: [(0, 5)]);
        expect(md, contains('hello'));
        expect(md, isNot(contains('world')));
      });
    });
  });
}
