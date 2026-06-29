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
    final match = _frontmatterPattern.firstMatch(fileContent);

    if (match != null) {
      final yamlBlock = match.group(1)!;
      final content = fileContent.substring(match.end);

      try {
        final yamlMap = loadYaml(yamlBlock);
        if (yamlMap is YamlMap) {
          final frontmatter = PageFrontmatter.fromYamlMap(yamlMap);
          return (
            frontmatter: frontmatter,
            content: _normalizeContent(content),
          );
        }
      } catch (_) {}
    }

    return (
      frontmatter: _freshFrontmatter(),
      content: _normalizeContent(fileContent),
    );
  }

  static String encode(PageFrontmatter frontmatter, String content) {
    final fm = frontmatter.toYamlMap();
    final buffer = StringBuffer();
    buffer.writeln('---');
    fm.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(content);
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
}
