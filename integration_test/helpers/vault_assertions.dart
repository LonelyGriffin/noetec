import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:path/path.dart' as p;

Future<void> expectVaultJsonValid(
  String vaultPath, {
  required String name,
}) async {
  final vaultFile = File(p.join(vaultPath, '.noetec', 'vault.json'));
  expect(await vaultFile.exists(), isTrue);
  final content =
      json.decode(await vaultFile.readAsString()) as Map<String, dynamic>;
  expect(content['name'], equals(name));
  expect(content['rootPath'], equals(vaultPath));
}

Future<void> expectDeviceIdentityExists(String vaultPath) async {
  expect(
    await File(p.join(vaultPath, '.noetec', 'device.json')).exists(),
    isTrue,
  );
}

String _walPath(String vaultPath, String relativePath) {
  return p.join(vaultPath, '.noetec', 'wal', relativePath);
}

String _oplogDir(String vaultPath, String relativePath) {
  return p.join(vaultPath, '.sync', relativePath);
}

Future<void> expectCrashRecoveryLogExists(
  String vaultPath,
  String relativePath,
) async {
  final walFile = File(_walPath(vaultPath, relativePath));
  expect(
    await walFile.exists(),
    isTrue,
    reason: 'Crash recovery log should exist for $relativePath',
  );
}

Future<void> expectCrashRecoveryLogContains(
  String vaultPath,
  String relativePath, {
  required String actionType,
  String? text,
}) async {
  final walFile = File(_walPath(vaultPath, relativePath));
  expect(
    await walFile.exists(),
    isTrue,
    reason: 'Crash recovery log should exist for $relativePath',
  );

  final raw = await walFile.readAsString();
  final lines = raw
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  expect(lines, isNotEmpty, reason: 'Crash recovery log should not be empty');

  final hasMatchingType = lines.any((line) {
    final entry = json.decode(line) as Map<String, dynamic>;
    return entry['type'] == actionType;
  });
  expect(
    hasMatchingType,
    isTrue,
    reason: 'Crash recovery log should contain action type "$actionType"',
  );

  if (text != null) {
    final hasMatchingText = lines.any((line) {
      final entry = json.decode(line) as Map<String, dynamic>;
      if (entry['type'] != 'insert_text') return false;
      final entryText = entry['text'] as String?;
      return entryText != null && entryText.contains(text);
    });
    expect(
      hasMatchingText,
      isTrue,
      reason: 'Crash recovery log should contain insert_text with "$text"',
    );
  }
}

Future<void> expectCrashRecoveryLogAbsent(
  String vaultPath,
  String relativePath,
) async {
  final walFile = File(_walPath(vaultPath, relativePath));
  expect(
    await walFile.exists(),
    isFalse,
    reason: 'Crash recovery log should NOT exist for $relativePath',
  );
}

Future<void> expectOpLogExists(String vaultPath, String relativePath) async {
  final dir = Directory(_oplogDir(vaultPath, relativePath));
  expect(
    await dir.exists(),
    isTrue,
    reason: 'OpLog directory should exist for $relativePath',
  );

  final oplogFiles = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.oplog.jsonl'))
      .toList();
  expect(
    oplogFiles,
    isNotEmpty,
    reason: 'OpLog directory should contain at least one .oplog.jsonl file',
  );
}

Future<void> expectOpLogContains(
  String vaultPath,
  String relativePath, {
  required String entryType,
}) async {
  final dir = Directory(_oplogDir(vaultPath, relativePath));
  expect(
    await dir.exists(),
    isTrue,
    reason: 'OpLog directory should exist for $relativePath',
  );

  final oplogFiles = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.oplog.jsonl'))
      .cast<File>()
      .toList();
  expect(
    oplogFiles,
    isNotEmpty,
    reason: 'OpLog directory should contain at least one .oplog.jsonl file',
  );

  for (final file in oplogFiles) {
    final raw = await file.readAsString();
    final lines = raw
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (final line in lines) {
      final entry = json.decode(line) as Map<String, dynamic>;
      if (entry['type'] == entryType) return;
    }
  }

  fail('OpLog should contain entry with type "$entryType" for $relativePath');
}

Future<void> expectOpLogDoesNotContain(
  String vaultPath,
  String relativePath, {
  required String entryType,
}) async {
  final dir = Directory(_oplogDir(vaultPath, relativePath));
  final dirExists = await dir.exists();
  if (!dirExists) return;

  final oplogFiles = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.oplog.jsonl'))
      .cast<File>()
      .toList();

  for (final file in oplogFiles) {
    final raw = await file.readAsString();
    final lines = raw
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (final line in lines) {
      final entry = json.decode(line) as Map<String, dynamic>;
      if (entry['type'] == entryType) {
        fail(
          'OpLog should NOT contain entry with type "$entryType" for $relativePath',
        );
      }
    }
  }
}

Future<void> expectOpLogAbsent(String vaultPath, String relativePath) async {
  final dir = Directory(_oplogDir(vaultPath, relativePath));
  final dirExists = await dir.exists();
  if (!dirExists) return;

  final oplogFiles = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.oplog.jsonl'))
      .toList();
  expect(
    oplogFiles,
    isEmpty,
    reason: 'OpLog should NOT exist for $relativePath',
  );
}

Future<void> expectPageFileValid(
  String vaultPath,
  String relativePath, {
  String? containsText,
}) async {
  final file = File(p.join(vaultPath, relativePath));
  expect(
    await file.exists(),
    isTrue,
    reason: 'Page file $relativePath should exist',
  );

  final raw = await file.readAsString();
  final (:frontmatter, :content) = PageFrontmatterCodec.parse(raw);

  expect(frontmatter.id, isNotEmpty, reason: 'Frontmatter should have id');
  expect(
    frontmatter.contentHash,
    isNotEmpty,
    reason: 'Frontmatter should have content_hash',
  );
  expect(
    frontmatter.contentHash,
    startsWith('sha256:'),
    reason: 'content_hash should start with sha256:',
  );

  expect(
    raw,
    contains(':::'),
    reason: 'Page should contain at least one ::: block directive',
  );

  if (containsText != null) {
    expect(
      raw,
      contains(containsText),
      reason: 'Page file should contain "$containsText"',
    );
  }
}

Future<String> readContentHash(String vaultPath, String relativePath) async {
  final file = File(p.join(vaultPath, relativePath));
  final raw = await file.readAsString();
  final (:frontmatter, :content) = PageFrontmatterCodec.parse(raw);
  return frontmatter.contentHash;
}

Future<void> expectPageFileContentHashChanged(
  String vaultPath,
  String relativePath,
  String oldHash,
) async {
  final newHash = await readContentHash(vaultPath, relativePath);
  expect(
    newHash,
    isNot(equals(oldHash)),
    reason: 'content_hash should have changed from $oldHash',
  );
}
