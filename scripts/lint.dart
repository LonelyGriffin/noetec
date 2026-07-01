// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

import 'common/lint_runner.dart';
import 'common/run_process.dart';

Future<void> main() async {
  print('📋 Lint — all changed files');
  print('');
  final success = await runLint(stagedOnly: false);

  print('');
  print('ℹ️ Outdated packages');
  await runProcess('dart', ['pub', 'outdated']);
  print('⚠️ Non-blocking: outdated check does not affect exit code');

  print('');
  _printSummary(success);
  exit(success ? 0 : 1);
}

void _printSummary(bool success) {
  print('📋 Summary');
  if (success) {
    print('🚀 All checks passed');
  } else {
    print('🛑 Some checks failed');
  }
}
