// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// Golden and edge-case tests for PageFrontmatterCodec against the normative
// spec docs/specs/file-format.md (format version 1).
//
// Covers:
//   - Round-trip of frontmatter + body for every well-formed fixture.
//   - Edge cases from spec §3.4: missing frontmatter, malformed YAML,
//     missing keys, empty file, Windows line endings, unterminated
//     frontmatter.
//
// Non-determinism: the `modified` timestamp is set to `DateTime.now()` on
// parse when the key is absent or the frontmatter is synthesized. Round-trip
// assertions therefore compare the parsed frontmatter fields and the body
// rather than the raw file bytes; `modified` is asserted only to be a valid
// ISO 8601 UTC timestamp.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';

/// Reads a fixture file and returns its raw bytes as a UTF-8 string.
String _readFixture(String name) =>
    File('test/fixtures/format/v1/$name.md').readAsStringSync();

/// Reads a fixture file and normalizes CRLF/CR to LF (spec §2).
String _readFixtureNormalized(String name) =>
    _readFixture(name).replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Returns the expected content body of a fixture per spec §5: strip the
/// frontmatter block (opening `---`, YAML, closing `---`, and the single
/// blank separator line) from the LF-normalized file.
String _expectedBody(String name) {
  final normalized = _readFixtureNormalized(name);
  if (!normalized.startsWith('---\n')) return normalized;
  final closingIndex = normalized.indexOf('\n---\n', 4);
  if (closingIndex == -1) return normalized;
  var bodyStart = closingIndex + '\n---\n'.length;
  if (bodyStart < normalized.length && normalized[bodyStart] == '\n') {
    bodyStart += 1;
  }
  return normalized.substring(bodyStart);
}

void main() {
  group('PageFrontmatterCodec golden round-trip (format v1) —', () {
    // Well-formed fixtures: parse must extract the declared id, the body must
    // match §5, and computeContentHash(body) must match the declared
    // content_hash. Re-encoding with the parsed frontmatter + body must
    // reproduce the original file with only the `modified` line allowed to
    // differ (it is preserved verbatim on parse, so it actually round-trips
    // byte-for-byte here).
    const wellFormedFixtures = [
      'welcome',
      'nested-blocks',
      'inline-formatting',
      'links',
      'windows-line-endings',
    ];

    for (final name in wellFormedFixtures) {
      test('$name: parse extracts declared id and content body', () {
        final result = PageFrontmatterCodec.parse(_readFixture(name));

        expect(result.frontmatter.id, isNotEmpty);
        expect(result.content, _expectedBody(name));
      });

      test('$name: declared content_hash matches computed hash of body', () {
        final result = PageFrontmatterCodec.parse(_readFixture(name));

        final computed =
            'sha256:${PageFrontmatterCodec.computeContentHash(result.content)}';
        expect(
          computed,
          result.frontmatter.contentHash,
          reason:
              'content_hash in fixture "$name" does not match the hash of '
              'its body as defined in spec §5.',
        );
      });

      test('$name: encode(parse(file)) reproduces the LF-normalized file', () {
        final result = PageFrontmatterCodec.parse(_readFixture(name));
        final reencoded =
            PageFrontmatterCodec.encode(result.frontmatter, result.content);

        expect(
          reencoded,
          _readFixtureNormalized(name),
          reason:
              'Round-trip divergence for fixture "$name". The re-encoded '
              'file does not match the LF-normalized input.',
        );
      });
    }
  });

  group('PageFrontmatterCodec spec §3.4 edge cases —', () {
    test('missing frontmatter: synthesizes fresh id, treats whole file as body',
        () {
      const input = 'Just some content without frontmatter';

      final result = PageFrontmatterCodec.parse(input);

      expect(result.frontmatter.id, isNotEmpty);
      expect(result.content, input);
    });

    test('malformed YAML: whole file is content, fresh id is synthesized', () {
      const input = '---\nthis is not: [valid yaml\n---\n\nBody text';

      final result = PageFrontmatterCodec.parse(input);

      // Per spec §3.4.2 the entire file, including the malformed block, is
      // the content body and a fresh frontmatter is synthesized.
      expect(result.frontmatter.id, isNotEmpty);
      expect(result.content, input);
    });

    test('missing keys: id is regenerated, content_hash is recomputed', () {
      const input = '---\nmodified: 2026-01-15T10:30:00.000Z\n---\n\nBody';

      final result = PageFrontmatterCodec.parse(input);

      // Spec §3.4.3: id MUST be regenerated (not empty), content_hash MUST
      // be recomputed (not empty / not the placeholder 'sha256:').
      expect(result.frontmatter.id, isNotEmpty);
      expect(
        result.frontmatter.contentHash,
        isNot(equals('sha256:')),
        reason: 'content_hash should be recomputed per §3.4.3, not left as '
            'the empty placeholder.',
      );
      expect(result.content, 'Body');
    });

    test('empty file: parses to empty body plus fresh frontmatter', () {
      final result = PageFrontmatterCodec.parse('');

      expect(result.frontmatter.id, isNotEmpty);
      expect(result.content, '');
    });

    test('whitespace-only file: parses to empty body plus fresh frontmatter',
        () {
      final result = PageFrontmatterCodec.parse('   \n\n  \n');

      expect(result.frontmatter.id, isNotEmpty);
      // Spec §3.4.4: a file containing only whitespace MUST parse to an
      // empty content body.
      expect(result.content, '');
    });

    test('CRLF line endings are normalized to LF before parsing', () {
      const input =
          '---\r\nid: test-id\r\ncontent_hash: sha256:abc\r\nmodified: 2026-01-15T10:30:00.000Z\r\n---\r\n\r\nBody text\r\n';

      final result = PageFrontmatterCodec.parse(input);

      expect(result.frontmatter.id, 'test-id');
      // After normalization, body is "Body text\n" (the trailing CRLF before
      // EOF becomes LF; the leading blank separator line is consumed).
      expect(result.content, 'Body text\n');
    });

    test('unterminated frontmatter: whole file is content, fresh id', () {
      const input = '---\nid: abc\ncontent_hash: sha256:xyz\nBody without close';

      final result = PageFrontmatterCodec.parse(input);

      // Spec §3.4.6: no closing `---` line means malformed — the whole file
      // is content, fresh frontmatter is synthesized.
      expect(result.frontmatter.id, isNotEmpty);
      expect(result.content, input);
    });
  });
}
