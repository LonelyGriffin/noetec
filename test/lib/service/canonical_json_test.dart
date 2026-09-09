// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:canonical_json/canonical_json.dart' as cj;
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for `canonicalJson` per `docs/specs/sync-security.md` §2.2.
///
/// The canonical form is now the OLPC Canonical JSON produced by the
/// `canonical_json` package (no local wrapper). These tests pin the exact
/// wire behavior the signing input depends on so that a future package
/// upgrade (major version) that changes any of it fails the suite instead of
/// silently changing signed bytes.
void main() {
  String encode(Object? value) => utf8.decode(cj.canonicalJson.encode(value));

  group('canonicalJson (§2.2 wire contract) —', () {
    test('primitives: int, bool, string, null', () {
      expect(encode(true), 'true');
      expect(encode(false), 'false');
      expect(encode(0), '0');
      expect(encode(-42), '-42');
      expect(encode('hi'), '"hi"');
      expect(encode(''), '""');
      expect(encode(null), 'null');
    });

    test('empty containers', () {
      expect(encode(<String, Object?>{}), '{}');
      expect(encode(<Object?>[]), '[]');
    });

    test('golden: keys sorted lexicographically (UTF-8 byte order)', () {
      final map = <String, Object?>{
        'zeta': 1,
        'alpha': {
          'nested': 'value',
          'beta': [3, 2, 1],
        },
        'mid': null,
      };
      final result = encode(map);
      expect(result, '{"alpha":{"beta":[3,2,1],"nested":"value"},"mid":null,"zeta":1}');

      // Deterministic: a shuffled copy yields identical bytes.
      final shuffled = <String, Object?>{
        'mid': null,
        'zeta': 1,
        'alpha': {
          'nested': 'value',
          'beta': [3, 2, 1],
        },
      };
      expect(encode(shuffled), result);
    });

    test('round-trips unknown keys (stable for arbitrary key sets)', () {
      final keys = ['k10', 'k2', 'k1', 'K9', 'a-b', 'a.b'];
      final map = <String, Object?>{for (final k in keys) k: k.length};
      final first = encode(map);
      final reversed = <String, Object?>{for (final k in keys.reversed) k: k.length};
      expect(encode(reversed), first);

      // '-' (0x2D) sorts before '.' (0x2E); uppercase before lowercase.
      final ordered = ['K9', 'a-b', 'a.b', 'k1', 'k10', 'k2'];
      expect(first, '{${ordered.map((k) => '"$k":${k.length}').join(',')}}');
    });

    test('arrays keep stored order', () {
      expect(encode([3, 1, 2]), '[3,1,2]');
      expect(
        encode([
          [1, 2],
          [3],
        ]),
        '[[1,2],[3]]',
      );
    });

    test('nulls are NOT omitted (spec §2.2)', () {
      final map = <String, Object?>{'a': 1, 'b': null, 'c': true};
      expect(encode(map), '{"a":1,"b":null,"c":true}');
      expect(encode([1, null]), '[1,null]');
    });

    test('escapes only quotes and backslash; control chars stay raw', () {
      expect(encode('a"b'), r'"a\"b"');
      expect(encode('a\\b'), r'"a\\b"');
      // Newline (U+000A) and tab (U+0009) are emitted as raw bytes, not
      // \n / \t escapes — that is the OLPC encoding §2.2 adopts.
      expect(cj.canonicalJson.encode('a\nb'), [34, 97, 10, 98, 34]);
      expect(cj.canonicalJson.encode('a\tb'), [34, 97, 9, 98, 34]);
    });

    test('emits non-ASCII as raw UTF-8', () {
      expect(encode('привет'), '"привет"');
      expect(cj.canonicalJson.encode('🎉'), utf8.encode('"🎉"'));
    });

    test('NFC-normalizes strings (decomposed == precomposed)', () {
      // é = U+00E9 (precomposed) vs 'e' + U+0301 (combining acute).
      final precomposed = encode({'é': 1});
      final decomposed = encode({'e\u0301': 1});
      expect(decomposed, precomposed);
      expect(precomposed, '{"é":1}');
    });

    test('rejects non-integer doubles and non-JSON types', () {
      expect(() => encode(1.5), throwsA(isA<ArgumentError>()));
      expect(() => encode(-0.0), throwsA(isA<ArgumentError>()));
      expect(() => encode(double.nan), throwsA(isA<UnsupportedError>()));
      expect(() => encode(double.infinity), throwsA(isA<UnsupportedError>()));
      expect(() => encode(Object()), throwsA(isA<ArgumentError>()));
    });

    test('decode validates canonical form and round-trips', () {
      final bytes = cj.canonicalJson.encode({
        'b': 2,
        'a': [1],
      });
      expect(cj.canonicalJson.decode(bytes), {
        'b': 2,
        'a': [1],
      });
      // Re-encoding the decoded value reproduces the exact same bytes.
      final decoded = cj.canonicalJson.decode(bytes);
      expect(cj.canonicalJson.encode(decoded), bytes);

      // Non-canonical inputs (whitespace, unsorted keys) are rejected.
      expect(() => cj.canonicalJson.decode(utf8.encode('{"a": 1}')), throwsException);
      expect(() => cj.canonicalJson.decode(utf8.encode('{"b":1,"a":2}')), throwsException);
    });
  });
}
