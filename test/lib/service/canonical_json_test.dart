// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/canonical_json.dart';

void main() {
  group('canonicalJson —', () {
    test('primitives', () {
      expect(canonicalJson(true), 'true');
      expect(canonicalJson(false), 'false');
      expect(canonicalJson(0), '0');
      expect(canonicalJson(-42), '-42');
      expect(canonicalJson(1.5), '1.5');
      expect(canonicalJson('hi'), '"hi"');
      expect(canonicalJson(''), '""');
    });

    test('empty containers', () {
      expect(canonicalJson(<String, dynamic>{}), '{}');
      expect(canonicalJson(<dynamic>[]), '[]');
    });

    test('golden: nested map is deterministic with lexicographic key order', () {
      // Keys intentionally out of order.
      final map = <String, dynamic>{
        'zeta': 1,
        'alpha': {
          'nested': 'value',
          'beta': [3, 2, 1],
        },
        'mid': null, // must be omitted
      };
      final result = canonicalJson(map);
      // alpha before mid (omitted) before zeta; inside alpha: beta before nested.
      expect(result, '{"alpha":{"beta":[3,2,1],"nested":"value"},"zeta":1}');

      // Deterministic: re-serializing a shuffled copy gives the same bytes.
      final shuffled = <String, dynamic>{
        'zeta': 1,
        'mid': null,
        'alpha': {
          'beta': [3, 2, 1],
          'nested': 'value',
        },
      };
      expect(canonicalJson(shuffled), result);
    });

    test('round-trips unknown keys (stable for arbitrary key sets)', () {
      final keys = ['k10', 'k2', 'k1', 'K9', 'a-b', 'a.b'];
      final map = <String, dynamic>{for (final k in keys) k: k.length};
      final first = canonicalJson(map);
      // Same logical object, different insertion order, must be identical.
      final reversed = <String, dynamic>{
        for (final k in keys.reversed) k: k.length,
      };
      expect(canonicalJson(reversed), first);

      // Keys are sorted by UTF-8 code point order: uppercase sorts before
      // lowercase in ASCII, and '-' (0x2D) sorts before '.' (0x2E).
      final ordered = ['K9', 'a-b', 'a.b', 'k1', 'k10', 'k2'];
      expect(
        first,
        '{'
        '${ordered.map((k) => '"$k":${k.length}').join(',')}'
        '}',
      );
    });

    test('arrays keep stored order', () {
      expect(canonicalJson([3, 1, 2]), '[3,1,2]');
      expect(
        canonicalJson([
          [1, 2],
          [3],
        ]),
        '[[1,2],[3]]',
      );
    });

    test('escapes control characters, quotes and backslash', () {
      expect(canonicalJson('a"b'), r'"a\"b"');
      expect(canonicalJson('a\b'), r'"a\b"');
      expect(canonicalJson('a\nb'), r'"a\nb"');
      expect(canonicalJson('a\tb'), r'"a\tb"');
      expect(canonicalJson('a\\b'), r'"a\\b"');
    });

    test('emits non-ASCII as raw UTF-8, not \\u escapes', () {
      // "привет" (Cyrillic) — each char is 2 UTF-8 bytes.
      final result = canonicalJson('привет');
      expect(result, '"привет"');
      // No \u escapes for printable non-ASCII.
      expect(result.contains(r'\u'), isFalse);
    });

    test('throws for unsupported top-level and list values', () {
      expect(() => canonicalJson(null), throwsUnsupportedError);
      expect(() => canonicalJson([1, null]), throwsUnsupportedError);
      expect(() => canonicalJson(double.nan), throwsUnsupportedError);
      expect(() => canonicalJson(double.infinity), throwsUnsupportedError);
      expect(() => canonicalJson(Object()), throwsUnsupportedError);
    });

    test('omits null-valued map keys but keeps others', () {
      final map = <String, dynamic>{'a': 1, 'b': null, 'c': true};
      expect(canonicalJson(map), '{"a":1,"c":true}');
    });

    test('sorts keys by UTF-8 byte order (astral chars after BMP)', () {
      // U+10000 (𐀀) encodes to 5 UTF-8 bytes (0xF0 …) and must sort after the
      // 1-byte ASCII key and the 2-byte BMP key. This is UTF-8 byte order, the
      // spec's "UTF-8 code point order".
      final map = <String, dynamic>{
        '\u{10000}': 3,
        'z': 1,
        '\u00E9': 2, // é, 2 UTF-8 bytes
      };
      expect(canonicalJson(map), '{"z":1,"\u00E9":2,"\u{10000}":3}');
    });
  });
}
