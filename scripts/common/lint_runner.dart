// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print

import 'changed_files.dart';
import 'check_copyright.dart';
import 'format_runner.dart';
import 'run_process.dart';

Future<bool> runLint({required bool stagedOnly}) async {
  final failures = <String>[];

  print('🔄 Format check');
  if (!await checkFormatting()) failures.add('format');

  print('');
  print('🔄 Static analysis');
  if (!await _runAnalyze()) failures.add('analyze');

  print('');
  print('🔄 Copyright check');
  final files = stagedOnly ? fetchStagedSourceFiles() : fetchChangedSourceFiles();
  if (!checkCopyrightInFiles(files)) failures.add('copyright');

  return failures.isEmpty;
}

Future<bool> _runAnalyze() => runProcess('dart', ['analyze'], failMessage: 'Static analysis found issues.', successMessage: 'No analysis issues.');
