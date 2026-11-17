// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print

import 'dart:io';

/// Heuristic review prompts, deliberately without suppressions or an exit code.
/// Canonical/wire paths can match too; a match is not a correctness verdict.
List<int> suspiciousPathLines(String source) {
  final patterns = [RegExp(r'''\.(?:split|lastIndexOf|indexOf)\(['"](?:/|\\\\)['"]\)'''), RegExp(r'''\$(?:\{[^}\r\n]+\}|[a-zA-Z_]\w*)/[^'"\r\n]*'''), RegExp(r'''['"]/vault/''')];
  final lines = source.split('\n');
  return [
    for (var index = 0; index < lines.length; index++)
      if (!lines[index].trimLeft().startsWith('//') && patterns.any((pattern) => pattern.hasMatch(lines[index]))) index + 1,
  ];
}

void reportPathAudit(Iterable<String> files) {
  print('ℹ️ Path audit — advisory only; review filesystem vs canonical/wire paths');
  var count = 0;
  try {
    for (final path in files.toSet().toList()..sort()) {
      if (!path.endsWith('.dart') || path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      for (final line in suspiciousPathLines(file.readAsStringSync())) {
        count++;
        if (count <= 20) print('  $path:$line — review manual path handling');
      }
    }
    if (count > 20) print('  … ${count - 20} additional suggestions');
    print('ℹ️ $count path review suggestions; this audit never affects the exit code.');
  } catch (error) {
    print('ℹ️ Path audit unavailable: $error (non-blocking)');
  }
}
