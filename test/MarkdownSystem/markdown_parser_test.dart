// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/MarkdownSystem/markdown_parser.dart';

void main() {
  late IdService idService;

  setUp(() {
    var idCounter = 0;
    idService = IdService(() => 'generated-id-${idCounter++}');
  });

  // ---------------------------------------------------------------------------
  // Plain paragraphs (no fenced directives)
  // ---------------------------------------------------------------------------

  group('Plain markdown paragraphs', () {
    test('parses single paragraph', () {
      final blocks = markdownToBlocks(
        'Hello World',
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 1);
      expect(blocks[0].computeAllSegmentsText(), 'Hello World');
      expect(blocks[0].id, 'generated-id-0');
    });

    test('parses multiple paragraphs', () {
      final blocks = markdownToBlocks(
        'First\n\nSecond\n\nThird',
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 3);
      expect(blocks[0].computeAllSegmentsText(), 'First');
      expect(blocks[1].computeAllSegmentsText(), 'Second');
      expect(blocks[2].computeAllSegmentsText(), 'Third');
    });

    test('parses bold text', () {
      final blocks = markdownToBlocks(
        'Hello **bold** world',
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 1);
      final segs = blocks[0].segments.value;
      expect(segs.length, 3);
      expect(segs[0].text, 'Hello ');
      expect(segs[0], isA<TextSegment>());
      expect(segs[1].text, 'bold');
      expect(segs[1], isA<FormattedSegment>());
      expect((segs[1] as FormattedSegment).format, TextFormat.bold);
      expect(segs[2].text, ' world');
    });

    test('parses italic text', () {
      final blocks = markdownToBlocks(
        '*italic*',
        idService: idService,
        documentId: 'doc',
      );

      final segs = blocks[0].segments.value;
      expect(segs.length, 1);
      expect(segs[0], isA<FormattedSegment>());
      expect((segs[0] as FormattedSegment).format, TextFormat.italic);
    });

    test('parses bold italic text', () {
      final blocks = markdownToBlocks(
        '***both***',
        idService: idService,
        documentId: 'doc',
      );

      final segs = blocks[0].segments.value;
      expect(segs.length, 1);
      expect(segs[0], isA<FormattedSegment>());
      expect((segs[0] as FormattedSegment).format, TextFormat.boldItalic);
    });

    test('parses link', () {
      final blocks = markdownToBlocks(
        'Click [here](https://example.com)',
        idService: idService,
        documentId: 'doc',
      );

      final segs = blocks[0].segments.value;
      expect(segs.length, 2);
      expect(segs[0].text, 'Click ');
      expect(segs[1], isA<LinkSegment>());
      expect((segs[1] as LinkSegment).text, 'here');
      expect((segs[1] as LinkSegment).url, 'https://example.com');
    });

    test('empty input produces one empty block', () {
      final blocks = markdownToBlocks(
        '',
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 1);
      expect(blocks[0].computeAllSegmentsText(), '');
    });
  });

  // ---------------------------------------------------------------------------
  // Fenced directives
  // ---------------------------------------------------------------------------

  group('Fenced directives', () {
    test('parses block with ID from fenced directive', () {
      final blocks = markdownToBlocks(
        '::: {#my-block-id}\nHello World\n:::',
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 1);
      expect(blocks[0].id, 'my-block-id');
      expect(blocks[0].computeAllSegmentsText(), 'Hello World');
    });

    test('parses multiple fenced directive blocks', () {
      final md = '::: {#b1}\nFirst\n:::\n\n::: {#b2}\nSecond\n:::';
      final blocks = markdownToBlocks(
        md,
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 2);
      expect(blocks[0].id, 'b1');
      expect(blocks[0].computeAllSegmentsText(), 'First');
      expect(blocks[1].id, 'b2');
      expect(blocks[1].computeAllSegmentsText(), 'Second');
    });

    test('parses fenced directive with formatted content', () {
      final md = '::: {#b1}\nHello **bold** and *italic*\n:::';
      final blocks = markdownToBlocks(
        md,
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 1);
      expect(blocks[0].id, 'b1');

      final segs = blocks[0].segments.value;
      expect(segs.length, 4);
      expect(segs[0].text, 'Hello ');
      expect(segs[1].text, 'bold');
      expect(segs[1], isA<FormattedSegment>());
      expect(segs[2].text, ' and ');
      expect(segs[3].text, 'italic');
      expect(segs[3], isA<FormattedSegment>());
    });

    test('mixed fenced directives and plain paragraphs', () {
      final md =
          '::: {#b1}\nFirst\n:::\n\nPlain paragraph\n\n::: {#b3}\nThird\n:::';
      final blocks = markdownToBlocks(
        md,
        idService: idService,
        documentId: 'doc',
      );

      expect(blocks.length, 3);
      expect(blocks[0].id, 'b1');
      expect(
        blocks[1].id,
        'generated-id-0',
        reason: 'Plain paragraph gets generated ID',
      );
      expect(blocks[2].id, 'b3');
    });
  });
}
