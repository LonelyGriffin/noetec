// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';

final class ClosingEvent {
  final List<Future<void>> _tasks = [];

  void waitFor(Future<void> task) => _tasks.add(task);

  Future<void> waitAll() async {
    if (_tasks.isEmpty) return;
    await Future.wait(_tasks);
  }
}
