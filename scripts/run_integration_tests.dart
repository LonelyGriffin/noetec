// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

import 'common/integration_test_runner.dart';

/// CLI entry point for running integration tests.
///
/// Runs each `integration_test/*_test.dart` file in its own `flutter test`
/// process, one file at a time by default (`--jobs 1`). This is the supported
/// way to run the integration suite in this environment: a bulk
/// `flutter test integration_test/` runs files in parallel and flakes under
/// WSLG ("Failed to load"), and `flutter test --concurrency` is ignored for
/// integration tests — so sequential per-file runs are required.
///
/// Usage:
///   dart run scripts/run_integration_tests.dart
///   dart run scripts/run_integration_tests.dart --filter rename
///   dart run scripts/run_integration_tests.dart --jobs 2
///   dart run scripts/run_integration_tests.dart integration_test/foo_test.dart
Future<void> main(List<String> args) async {
  var jobs = 1;
  String? filter;
  final explicitFiles = <String>[];
  final passthrough = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--jobs') {
      jobs = int.parse(args[++i]);
    } else if (a == '--filter') {
      filter = args[++i];
    } else if (a == '--') {
      passthrough.addAll(args.sublist(i + 1));
      break;
    } else if (a.startsWith('-')) {
      passthrough.add(a);
    } else {
      explicitFiles.add(a);
    }
  }

  var files = <String>[...explicitFiles];
  if (files.isEmpty) {
    final dir = Directory('integration_test');
    final discovered = <String>[];
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e is File && e.path.endsWith('_test.dart')) {
          discovered.add(e.path);
        }
      }
    }
    discovered.sort();
    files = discovered;
  }
  if (filter != null) {
    files = files.where((f) => f.contains(filter!)).toList();
  }

  if (files.isEmpty) {
    print('❌ No integration test files found.');
    exit(1);
  }

  print('🧪 Integration tests — ${files.length} file(s), jobs=$jobs');
  if (jobs > 1) {
    print(
      '⚠️ jobs>1 can flake under WSLG — use --jobs 1 if you see '
      '"Failed to load" errors.',
    );
  }
  print('');

  final runner = IntegrationTestRunner();
  final results = await runner.run(
    testFiles: files,
    jobs: jobs,
    passthroughArgs: passthrough,
    onFileComplete: (r) {
      final mark = r.passed ? '✅' : '❌';
      print('$mark ${r.file}  (${r.duration.inSeconds}s)');
      if (!r.passed) {
        final out = r.stdout.isEmpty ? r.stderr : r.stdout;
        print(_tail(out, 25));
        print('');
      }
    },
  );

  final failed = results.where((r) => !r.passed).toList();
  print('');
  print('🧪 Summary: ${results.length - failed.length}/${results.length} passed');
  if (failed.isNotEmpty) {
    print('🛑 Failed:');
    for (final r in failed) {
      print('   ❌ ${r.file}');
    }
    exit(1);
  }
  print('🚀 All integration tests passed');
  exit(0);
}

String _tail(String s, int lines) {
  final ls = s.split('\n');
  final start = ls.length > lines ? ls.length - lines : 0;
  return ls.sublist(start).join('\n');
}
