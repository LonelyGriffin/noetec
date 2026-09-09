// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

/// Canonical JSON serialization, per `docs/specs/sync-security.md` §2.2.
///
/// A stable, deterministic encoding of a JSON value so that the same logical
/// object always serializes to byte-identical output — which is what makes it
/// safe to use as the Ed25519 signing input.
///
/// Rules (from the spec):
///
/// - Object keys are sorted **lexicographically by UTF-8 code point order**.
/// - No whitespace beyond the `,` and `:` separators.
/// - Strings are UTF-8; printable, non-structural characters are emitted as-is
///   (not `\uXXXX` escapes), so the bytes are the raw UTF-8 of the string.
/// - Arrays keep their stored order (order is significant).
/// - Keys with a `null` value are **omitted**.
final class CanonicalJson {
  CanonicalJson._();

  /// The fixed set of JSON escape sequences for control characters, `"` and
  /// `\` (RFC 8259 §7).
  static const Map<int, String> _escapes = {
    0x08: r'\b',
    0x09: r'\t',
    0x0A: r'\n',
    0x0C: r'\f',
    0x0D: r'\r',
    0x22: r'\"',
    0x5C: r'\\',
  };

  /// Serializes [value] to its canonical JSON form.
  ///
  /// [value] must be a JSON-compatible value: `bool`, `int`, `double`, `String`,
  /// a `List` of such, or a `Map<String, ...>` of such. `null` values are
  /// omitted from maps (per the spec) and rejected in lists.
  static String encode(Object? value) {
    if (value == null) {
      throw UnsupportedError(
        'Canonical JSON does not support a null top-level value',
      );
    }
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        throw UnsupportedError('Canonical JSON does not support $value');
      }
      return value.toString();
    }
    if (value is String) return _encodeString(value);
    if (value is List) return _encodeList(value);
    if (value is Map) {
      final map = Map<String, Object?>.from(
        value.map((k, v) => MapEntry(k as String, v)),
      );
      return _encodeMap(map);
    }
    throw UnsupportedError(
      'Canonical JSON cannot serialize a ${value.runtimeType}',
    );
  }

  static String _encodeMap(Map<String, Object?> map) {
    final entries = map.entries.where((e) => e.value != null).toList()
      ..sort((a, b) => _compareUtf8(a.key, b.key));
    if (entries.isEmpty) return '{}';
    final parts = <String>[];
    for (final e in entries) {
      parts.add('${_encodeString(e.key)}:${encode(e.value)}');
    }
    return '{${parts.join(',')}}';
  }

  static String _encodeList(List<Object?> list) {
    if (list.isEmpty) return '[]';
    final parts = <String>[];
    for (final item in list) {
      if (item == null) {
        throw UnsupportedError(
          'Canonical JSON does not support null list items',
        );
      }
      parts.add(encode(item));
    }
    return '[${parts.join(',')}]';
  }

  /// Compares two strings by their **UTF-8 byte order** (the "UTF-8 code point
  /// order" the spec requires, `docs/specs/sync-security.md` §2.2).
  ///
  /// `String.compareTo` orders by UTF-16 code units, which disagrees with UTF-8
  /// byte order for characters outside the Basic Multilingual Plane (e.g.
  /// emoji). Comparing the raw UTF-8 bytes matches the spec exactly.
  static int _compareUtf8(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    final n = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
    for (var i = 0; i < n; i++) {
      final d = aBytes[i].compareTo(bBytes[i]);
      if (d != 0) return d;
    }
    return aBytes.length.compareTo(bBytes.length);
  }

  /// JSON string encoding (RFC 8259 §7).
  ///
  /// Emits the raw UTF-8 for printable, non-structural characters and escapes
  /// the control characters plus `"` and `\`. This is deterministic for a given
  /// input string (the same string always yields the same bytes).
  static String _encodeString(String s) {
    final buffer = StringBuffer('"');
    for (final rune in s.runes) {
      final escaped = _escapes[rune];
      if (escaped != null) {
        buffer.write(escaped);
      } else if (rune < 0x20) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.write(String.fromCharCode(rune));
      }
    }
    buffer.write('"');
    return buffer.toString();
  }
}

/// Returns the canonical JSON encoding of [value], per
/// `docs/specs/sync-security.md` §2.2.
///
/// Top-level convenience wrapper around [CanonicalJson.encode].
String canonicalJson(Object? value) => CanonicalJson.encode(value);
