// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';

import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:path/path.dart' as p;

final class ExternalEditEvent {
  final String relativePath;
  final String currentHash;
  final String knownHash;

  const ExternalEditEvent({
    required this.relativePath,
    required this.currentHash,
    required this.knownHash,
  });
}

class VaultWatcher {
  VaultWatcher({
    required IFileSystemService fileSystem,
    required String vaultRootPath,
    this.pollInterval = const Duration(seconds: 30),
  }) : _fileSystem = fileSystem,
       _pagesPath = p.join(vaultRootPath, 'pages'),
       _vaultRootPath = vaultRootPath;

  final IFileSystemService _fileSystem;
  final String _pagesPath;
  final String _vaultRootPath;
  final Duration pollInterval;

  final StreamController<ExternalEditEvent> _controller =
      StreamController<ExternalEditEvent>.broadcast();
  StreamSubscription<FileEntry>? _subscription;
  final Set<String> _acknowledged = {};

  Stream<ExternalEditEvent> get events => _controller.stream;

  bool get isRunning => _subscription != null;

  void start() {
    if (_subscription != null) return;
    _subscription = _fileSystem
        .watchDirectory(_pagesPath, pollInterval: pollInterval)
        .where((entry) => !entry.isDirectory && entry.name.endsWith('.md'))
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

    final raw = await _fileSystem.readFile(entry.path);
    final (:frontmatter, :content) = PageFrontmatterCodec.parse(raw);
    final currentHash =
        'sha256:${PageFrontmatterCodec.computeContentHash(content)}';
    final knownHash = frontmatter.contentHash;

    if (currentHash == knownHash) return;

    final relativePath = p
        .relative(entry.path, from: _vaultRootPath)
        .replaceAll('\\', '/');
    _controller.add(
      ExternalEditEvent(
        relativePath: relativePath,
        currentHash: currentHash,
        knownHash: knownHash,
      ),
    );
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
