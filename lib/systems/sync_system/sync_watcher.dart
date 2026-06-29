// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';

import 'package:noetec/service/file_system_service.dart';
import 'package:path/path.dart' as p;

final class SyncChangeEvent {
  final String relativePath;
  final String deviceUuid;
  final DateTime lastModified;

  const SyncChangeEvent({
    required this.relativePath,
    required this.deviceUuid,
    required this.lastModified,
  });
}

class SyncWatcher {
  SyncWatcher({
    required IFileSystemService fileSystem,
    required String vaultRootPath,
    required String ownDeviceUuid,
    this.pollInterval = const Duration(seconds: 10),
  }) : _fileSystem = fileSystem,
       _syncPagesPath = p.join(vaultRootPath, '.sync', 'pages'),
       _ownDeviceUuid = ownDeviceUuid;

  final IFileSystemService _fileSystem;
  final String _syncPagesPath;
  final String _ownDeviceUuid;
  final Duration pollInterval;

  final StreamController<SyncChangeEvent> _controller =
      StreamController<SyncChangeEvent>.broadcast();
  StreamSubscription<FileEntry>? _subscription;
  final Set<String> _acknowledged = {};

  Stream<SyncChangeEvent> get events => _controller.stream;

  bool get isRunning => _subscription != null;

  void start() {
    if (_subscription != null) return;
    _subscription = _fileSystem
        .watchDirectory(_syncPagesPath, pollInterval: pollInterval)
        .where((entry) => !entry.isDirectory)
        .where((entry) => entry.name.endsWith('.oplog.jsonl'))
        .listen(_onFileChanged);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void acknowledge(String path) {
    _acknowledged.add(path);
  }

  Future<void> _onFileChanged(FileEntry entry) async {
    if (_acknowledged.remove(entry.path)) return;

    final decoded = _decode(entry.path);
    if (decoded == null) return;
    final (:relativePath, :deviceUuid) = decoded;

    if (deviceUuid == _ownDeviceUuid) return;

    _controller.add(
      SyncChangeEvent(
        relativePath: relativePath,
        deviceUuid: deviceUuid,
        lastModified: entry.lastModified ?? DateTime.now(),
      ),
    );
  }

  ({String relativePath, String deviceUuid})? _decode(String absoluteFilePath) {
    final rel = p
        .relative(absoluteFilePath, from: _syncPagesPath)
        .replaceAll('\\', '/');
    if (rel.startsWith('..')) return null;
    final parts = p.split(rel);
    if (parts.length < 2) return null;

    final encodedDir = parts[0];
    final fileName = parts[1];
    if (!fileName.endsWith('.oplog.jsonl')) return null;

    final deviceUuid = fileName.substring(
      0,
      fileName.length - '.oplog.jsonl'.length,
    );
    try {
      final relativePath = Uri.decodeComponent(encodedDir);
      return (relativePath: relativePath, deviceUuid: deviceUuid);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
