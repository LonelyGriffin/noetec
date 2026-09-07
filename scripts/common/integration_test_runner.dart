// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class TestResult {
  final String file;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  TestResult({
    required this.file,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  bool get passed => exitCode == 0;
}

class IntegrationTestRunner {
  final List<Process> _activeProcesses = [];
  bool _interrupted = false;

  Future<List<TestResult>> run({
    required List<String> testFiles,
    required int jobs,
    required List<String> passthroughArgs,
    void Function(TestResult result)? onFileComplete,
  }) async {
    final semaphore = _Semaphore(jobs);
    final results = <TestResult>[];

    ProcessSignal.sigint.watch().listen((_) {
      _interrupted = true;
      for (final process in _activeProcesses) {
        process.kill();
      }
      exit(1);
    });

    final futures = testFiles.map((file) async {
      await semaphore.acquire();
      if (_interrupted) return;

      final stopwatch = Stopwatch()..start();
      Process process;
      try {
        // WSLg's GPU/EGL path breaks on the second app launch within a single
        // `flutter test` session ("The log reader stopped unexpectedly, or
        // never started"). Forcing Mesa software rendering makes launches
        // reliable on this headless WSL box; the runner injects these into
        // every child process.
        // On Windows `flutter` is `flutter.bat` (a batch script), which
        // CreateProcess can't execute directly — Dart's Process.start throws
        // "The system cannot find the file specified" unless we go through
        // the shell. `dart` works without this because it's `dart.exe`.
        // The Mesa software-rendering vars are Linux-only (WSL); on Windows
        // they're meaningless, so only inject them off-Windows.
        //
        // On Windows `flutter test` needs an explicit device: Windows desktop,
        // Chrome and Edge all count as "connected", so the tool refuses to
        // guess. Default to the Windows desktop app; override via `-- -d X`.
        final hasDeviceFlag = passthroughArgs.any(
          (a) => a == '-d' || a == '--device',
        );
        final testArgs = <String>[
          'test',
          file,
          if (Platform.isWindows && !hasDeviceFlag) ...['-d', 'windows'],
          ...passthroughArgs,
        ];
        process = await Process.start(
          'flutter',
          testArgs,
          runInShell: Platform.isWindows,
          environment: <String, String>{
            ...Platform.environment,
            if (!Platform.isWindows) ...{
              'LIBGL_ALWAYS_SOFTWARE': '1',
              'GALLIUM_DRIVER': 'llvmpipe',
            },
          },
        );
      } catch (e) {
        stopwatch.stop();
        semaphore.release();
        final result = TestResult(
          file: file,
          exitCode: 1,
          stdout: '',
          stderr: 'Failed to start flutter: $e',
          duration: stopwatch.elapsed,
        );
        results.add(result);
        onFileComplete?.call(result);
        return;
      }

      _activeProcesses.add(process);

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // Decode process output to UTF-8; writing the raw List<int> to a
      // StringBuffer would render as `[77, 111, 114, ...]` byte codes.
      process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

      final exitCode = await process.exitCode;
      stopwatch.stop();

      _activeProcesses.remove(process);
      semaphore.release();

      final result = TestResult(
        file: file,
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        duration: stopwatch.elapsed,
      );

      results.add(result);
      onFileComplete?.call(result);
    });

    await Future.wait(futures);
    return results;
  }
}

class _Semaphore {
  int _available;
  final Queue<Completer<void>> _waiters = Queue();

  _Semaphore(int count) : _available = count;

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeFirst();
      completer.complete();
    } else {
      _available++;
    }
  }
}
