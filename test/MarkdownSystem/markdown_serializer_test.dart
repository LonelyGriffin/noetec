// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/MarkdownSystem/markdown_serializer.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Plain text
  // ---------------------------------------------------------------------------

  group('Plain text serialization', () {
    test('single block with plain text', () {
      final block = TextBlock(
        id: 'block-1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: 'Hello World')]),
      );

      final md = blocksToMarkdown([block]);

      expect(md, '::: {#block-1}\nHello World\n:::\n');
    });

    test('multiple blocks', () {
      final b1 = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: 'First')]),
      );
      final b2 = TextBlock(
        id: 'b2',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: 'Second')]),
      );

      final md = blocksToMarkdown([b1, b2]);

      expect(md, '::: {#b1}\nFirst\n:::\n\n::: {#b2}\nSecond\n:::\n');
    });
  });

  // ---------------------------------------------------------------------------
  // Formatted text
  // ---------------------------------------------------------------------------

  group('Formatted text serialization', () {
    test('bold text', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(
          data: [
            const TextSegment(text: 'Hello '),
            const FormattedSegment(text: 'bold', format: TextFormat.bold),
            const TextSegment(text: ' world'),
          ],
        ),
      );

      final md = blocksToMarkdown([block]);

      expect(md, '::: {#b1}\nHello **bold** world\n:::\n');
    });

    test('italic text', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(
          data: [
            const FormattedSegment(text: 'italic', format: TextFormat.italic),
          ],
        ),
      );

      final md = blocksToMarkdown([block]);

      expect(md, '::: {#b1}\n*italic*\n:::\n');
    });

    test('bold italic text', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(
          data: [
            const FormattedSegment(text: 'both', format: TextFormat.boldItalic),
          ],
        ),
      );

      final md = blocksToMarkdown([block]);

      expect(md, '::: {#b1}\n***both***\n:::\n');
    });

    test('link segment', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(
          data: [
            const TextSegment(text: 'Click '),
            const LinkSegment(text: 'here', url: 'https://example.com'),
          ],
        ),
      );

      final md = blocksToMarkdown([block]);

      expect(md, '::: {#b1}\nClick [here](https://example.com)\n:::\n');
    });
  });

  // ---------------------------------------------------------------------------
  // Ranges (partial block serialization)
  // ---------------------------------------------------------------------------

  group('Partial block serialization with ranges', () {
    test('serializes only the specified character range', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: 'Hello World')]),
      );

      final md = blocksToMarkdown([block], ranges: [(6, 11)]);

      expect(md, '::: {#b1}\nWorld\n:::\n');
    });

    test('null range serializes full block', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: 'Full')]),
      );

      final md = blocksToMarkdown([block], ranges: [null]);

      expect(md, '::: {#b1}\nFull\n:::\n');
    });
  });
}
