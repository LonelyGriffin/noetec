// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

import 'common/check_copyright.dart';

Future<void> main() async {
  final failures = <String>[];

  print('=== Format check ===');
  if (!await _runFormatCheck()) failures.add('format');

  print('');
  print('=== Static analysis ===');
  if (!await _runAnalyze()) failures.add('analyze');

  print('');
  print('=== Copyright check ===');
  if (!_runCopyrightCheck()) failures.add('copyright');

  print('');
  print('=== Outdated packages (info) ===');
  await _runOutdatedInfo();

  print('');
  _printSummary(failures);
  exit(failures.isEmpty ? 0 : 1);
}

Future<bool> _runFormatCheck() async {
  final result = await Process.run('dart', [
    'format',
    '--set-exit-if-changed',
    '.',
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    print('FAIL: formatting issues detected.');
    return false;
  }
  print('OK: all files formatted correctly.');
  return true;
}

Future<bool> _runAnalyze() async {
  final result = await Process.run('dart', ['analyze']);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    print('FAIL: static analysis found issues.');
    return false;
  }
  print('OK: no analysis issues.');
  return true;
}

bool _runCopyrightCheck() {
  final filesWithoutCopyright = <String>[];

  filesWithoutCopyright.addAll(findFilesWithoutCopyright('lib'));
  filesWithoutCopyright.addAll(findFilesWithoutCopyright('scripts'));

  if (filesWithoutCopyright.isNotEmpty) {
    print('FAIL: files missing copyright headers:');
    for (final file in filesWithoutCopyright) {
      print('- $file');
    }
    return false;
  }

  print('OK: all source files have correct copyright header.');
  return true;
}

Future<void> _runOutdatedInfo() async {
  final result = await Process.run('dart', ['pub', 'outdated']);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  print('(non-blocking: outdated check does not affect exit code)');
}

void _printSummary(List<String> failures) {
  print('=== Summary ===');
  if (failures.isEmpty) {
    print('All checks passed.');
  } else {
    print('Failed checks: ${failures.join(', ')}');
  }
}
