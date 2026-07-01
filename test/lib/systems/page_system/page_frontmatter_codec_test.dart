// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';

void main() {
  group('PageFrontmatterCodec —', () {
    group('parse —', () {
      test('parses valid frontmatter and content', () {
        const fileContent = '''---
id: test-id-123
content_hash: sha256:abc123
modified: 2026-01-15T10:30:00.000Z
---

Hello world''';

        final result = PageFrontmatterCodec.parse(fileContent);

        expect(result.frontmatter.id, 'test-id-123');
        expect(result.frontmatter.contentHash, 'sha256:abc123');
        expect(result.content, 'Hello world');
      });

      test('generates fresh frontmatter for file without frontmatter', () {
        const fileContent = 'Just some content without frontmatter';

        final result = PageFrontmatterCodec.parse(fileContent);

        expect(result.frontmatter.id, isNotEmpty);
        expect(result.content, 'Just some content without frontmatter');
      });

      test('handles file with only frontmatter and no content', () {
        const fileContent = '''---
id: test-id
content_hash: sha256:abc
modified: 2026-01-15T10:30:00.000Z
---
''';

        final result = PageFrontmatterCodec.parse(fileContent);

        expect(result.frontmatter.id, 'test-id');
        expect(result.content, '');
      });
    });

    group('encode —', () {
      test('produces valid frontmatter block followed by content', () {
        final frontmatter = PageFrontmatter(
          id: 'enc-id',
          contentHash: 'sha256:def456',
          modified: DateTime.utc(2026, 6, 12, 10, 0),
        );

        final encoded = PageFrontmatterCodec.encode(frontmatter, 'Hello');

        expect(encoded, contains('---'));
        expect(encoded, contains('id: enc-id'));
        expect(encoded, contains('content_hash: sha256:def456'));
        expect(encoded, contains('Hello'));
      });

      test('roundtrip: encode then parse produces same data', () {
        final original = PageFrontmatter(
          id: 'round-trip-id',
          contentHash: 'sha256:xyz',
          modified: DateTime.utc(2026, 3, 1, 12, 0),
        );
        const content = 'Round trip content';

        final encoded = PageFrontmatterCodec.encode(original, content);
        final decoded = PageFrontmatterCodec.parse(encoded);

        expect(decoded.frontmatter.id, original.id);
        expect(decoded.frontmatter.contentHash, original.contentHash);
        expect(decoded.content, content);
      });
    });

    group('computeContentHash —', () {
      test('returns sha256 hex digest', () {
        final hash = PageFrontmatterCodec.computeContentHash('hello');

        expect(hash, isNotEmpty);
        expect(hash.length, 64);
      });

      test('returns same hash for same content', () {
        final hash1 = PageFrontmatterCodec.computeContentHash('test');
        final hash2 = PageFrontmatterCodec.computeContentHash('test');

        expect(hash1, hash2);
      });
    });
  });
}
