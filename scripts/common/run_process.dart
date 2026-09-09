// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

Future<bool> runProcess(String executable, List<String> args, {String? failMessage, String? successMessage}) async {
  final result = await Process.run(executable, args);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    if (failMessage != null) print('❌ $failMessage');
    return false;
  }
  if (successMessage != null) print('✅ $successMessage');
  return true;
}
