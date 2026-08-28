// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

final class PageFrontmatter {
  final String id;
  final String contentHash;
  final DateTime modified;
  final String? modifiedBy;

  const PageFrontmatter({
    required this.id,
    required this.contentHash,
    required this.modified,
    this.modifiedBy,
  });

  PageFrontmatter copyWith({
    String? id,
    String? contentHash,
    DateTime? modified,
    String? modifiedBy,
  }) => PageFrontmatter(
    id: id ?? this.id,
    contentHash: contentHash ?? this.contentHash,
    modified: modified ?? this.modified,
    modifiedBy: modifiedBy ?? this.modifiedBy,
  );

  factory PageFrontmatter.fromYamlMap(YamlMap map) {
    return PageFrontmatter(
      id: map['id'] as String? ?? const Uuid().v4(),
      contentHash: map['content_hash'] as String? ?? '',
      modified: map['modified'] != null
          ? DateTime.parse(map['modified'] as String)
          : DateTime.now().toUtc(),
      modifiedBy: map['modified_by'] as String?,
    );
  }

  Map<String, dynamic> toYamlMap() {
    final map = <String, dynamic>{
      'id': id,
      'content_hash': contentHash,
      'modified': modified.toIso8601String(),
    };
    if (modifiedBy != null) {
      map['modified_by'] = modifiedBy;
    }
    return map;
  }
}

class PageFrontmatterCodec {
  PageFrontmatterCodec._();

  static const _uuid = Uuid();

  static final _frontmatterPattern = RegExp(
    r'^---\r?\n(.*?)\r?\n---\r?\n?',
    dotAll: true,
  );

  static ({PageFrontmatter frontmatter, String content}) parse(
    String fileContent,
  ) {
    // Spec §2: on read the parser MUST normalize CRLF and lone CR line
    // endings to LF before any further processing (frontmatter detection,
    // hash computation, block parsing). The LF-only form is canonical.
    final normalized = _normalizeLineEndings(fileContent);

    final match = _frontmatterPattern.firstMatch(normalized);

    if (match != null) {
      final yamlBlock = match.group(1)!;
      final content = _normalizeContent(normalized.substring(match.end));

      try {
        final yamlMap = loadYaml(yamlBlock);
        if (yamlMap is YamlMap) {
          var frontmatter = PageFrontmatter.fromYamlMap(yamlMap);
          // Spec §3.4.3: a missing content_hash MUST be recomputed per §5.
          if (frontmatter.contentHash.isEmpty) {
            frontmatter = frontmatter.copyWith(
              contentHash: 'sha256:${computeContentHash(content)}',
            );
          }
          return (frontmatter: frontmatter, content: content);
        }
      } catch (_) {}
    }

    // Spec §3.4.1/2/6: missing, malformed, or unterminated frontmatter —
    // the whole normalized file is the content body and a fresh frontmatter
    // is synthesized.
    // Spec §3.4.4: an empty or whitespace-only file parses to an empty
    // content body.
    return (
      frontmatter: _freshFrontmatter(),
      content: _emptyIfWhitespaceOnly(normalized),
    );
  }

  static String encode(PageFrontmatter frontmatter, String content) {
    // Spec §2: on write all line endings in the file MUST be LF.
    final normalized = _normalizeLineEndings(content);
    final fm = frontmatter.toYamlMap();
    final buffer = StringBuffer();
    buffer.writeln('---');
    fm.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(normalized);
    return buffer.toString();
  }

  static String computeContentHash(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  static PageFrontmatter _freshFrontmatter() => PageFrontmatter(
    id: _uuid.v4(),
    contentHash: 'sha256:',
    modified: DateTime.now().toUtc(),
  );

  static String _normalizeContent(String content) {
    if (content.startsWith('\r\n')) return content.substring(2);
    if (content.startsWith('\n')) return content.substring(1);
    return content;
  }

  /// Spec §2: normalizes CRLF and lone CR line endings to LF.
  static String _normalizeLineEndings(String content) =>
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Spec §3.4.4: an empty or whitespace-only file parses to an empty
  /// content body.
  static String _emptyIfWhitespaceOnly(String content) =>
      content.trim().isEmpty ? '' : content;
}
