// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:collection';
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
        process = await Process.start('flutter', [
          'test',
          file,
          ...passthroughArgs,
        ]);
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

      process.stdout.listen((data) => stdoutBuffer.write(data));
      process.stderr.listen((data) => stderrBuffer.write(data));

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
