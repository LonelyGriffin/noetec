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
/// process, one file at a time by default (`--jobs 1`). Sequential (`--jobs 1`)
/// is the only supported mode on the WSL daemon box: under WSLg the second
/// app launch within a single `flutter test` session fails ("Failed to load" /
/// "The log reader stopped unexpectedly"), so every file gets its own
/// `flutter test` process with software rendering forced
/// (`LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe`). `--jobs > 1` is
/// experimental and flakes under GPU/EGL contention. See the
/// `integration-testing` skill.
///
/// Usage:
///   dart run scripts/run_integration_tests.dart
///   dart run scripts/run_integration_tests.dart --filter rename
///   dart run scripts/run_integration_tests.dart --jobs 2
///   dart run scripts/run_integration_tests.dart integration_test/foo_test.dart
///   dart run scripts/run_integration_tests.dart integration_test/foo_test.dart --slow
///   dart run scripts/run_integration_tests.dart --speed 8 --hud-corner tl
///
/// Slow-motion (human-watchable) mode — off by default, no change to normal runs:
///   --slow                    enable the HUD + slowed animations
///   --speed n                 slowdown multiplier (timeDilation), default 4; implies --slow
///   --hud-corner tl|tr|bl|br  HUD panel corner, default br; implies --slow
/// They translate into `--dart-define=NOETEC_SLOW / NOETEC_SPEED / NOETEC_HUD_CORNER`
/// on the child `flutter test`; see `integration_test/helpers/slow_motion_hud.dart`.
Future<void> main(List<String> args) async {
  var jobs = 1;
  String? filter;
  var slow = false;
  int speed = 4;
  var hudCorner = 'br';
  final explicitFiles = <String>[];
  final passthrough = <String>[];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--jobs') {
      jobs = int.parse(args[++i]);
    } else if (a == '--filter') {
      filter = args[++i];
    } else if (a == '--slow') {
      slow = true;
    } else if (a == '--speed') {
      speed = int.tryParse(args[++i]) ?? 0;
      if (speed <= 0) {
        print('❌ --speed must be a positive integer.');
        exit(1);
      }
      slow = true;
    } else if (a == '--hud-corner') {
      hudCorner = args[++i];
      if (const ['tl', 'tr', 'bl', 'br'].contains(hudCorner) == false) {
        print('❌ --hud-corner must be one of: tl, tr, bl, br.');
        exit(1);
      }
      slow = true;
    } else if (a == '--') {
      passthrough.addAll(args.sublist(i + 1));
      break;
    } else if (a.startsWith('-')) {
      passthrough.add(a);
    } else {
      explicitFiles.add(a);
    }
  }
  if (slow) {
    passthrough.addAll(<String>['--dart-define=NOETEC_SLOW=true', '--dart-define=NOETEC_SPEED=$speed', '--dart-define=NOETEC_HUD_CORNER=$hudCorner']);
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
  if (slow) {
    print('🐢 Slow-motion mode: HUD corner=$hudCorner, timeDilation=$speed');
  }
  if (jobs > 1) {
    print(
      '⚠️ jobs>1 is EXPERIMENTAL and unsupported on WSLg: parallel runs '
      'flake under GPU/EGL contention. Prefer --jobs 1.',
    );
  }
  print(
    'ℹ️ Run the full suite with --jobs 1. If a file fails, re-run it alone '
    'in clean single-file isolation before reporting it as a regression — '
    'batch failures are usually WSLg contention, not code bugs.',
  );
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
    print(
      '💡 Re-run each failed file alone (--jobs 1, single file) before '
      'treating it as a regression — batch failures are usually WSLg '
      'contention.',
    );
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
