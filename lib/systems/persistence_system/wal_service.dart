// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';
import 'dart:convert';

import '../../entity/page/page_edit_action.dart';
import '../../service/file_system_service.dart';
import '../../systems/vault/vault_system.dart';
import 'wal_action_serializer.dart';

class WalEntry {
  const WalEntry({
    required this.relativePath,
    required this.walFilePath,
    required this.actionCount,
  });

  final String relativePath;
  final String walFilePath;
  final int actionCount;
}

class WalService {
  WalService(IFileSystemService fileSystem, VaultSystem vaultSystem)
    : _fs = fileSystem,
      _vaultSystem = vaultSystem,
      _serializer = const WalActionSerializer() {
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final IFileSystemService _fs;
  final VaultSystem _vaultSystem;
  final WalActionSerializer _serializer;

  String? _vaultRootPath;

  final Map<String, _ActionBuffer> _buffers = {};
  final Map<String, String> _pagePaths = {};

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      _vaultRootPath = vault.rootPath;
    } else {
      deactivate();
    }
  }

  void deactivate() {
    for (final buffer in _buffers.values) {
      buffer.timer?.cancel();
    }
    _buffers.clear();
    _pagePaths.clear();
    _vaultRootPath = null;
  }

  void register(String pageId, String relativePath) {
    _pagePaths[pageId] = relativePath;
  }

  void unregister(String pageId) {
    _buffers.remove(pageId)?.timer?.cancel();
    _pagePaths.remove(pageId);
  }

  void appendAction(String pageId, PageEditAction action) {
    if (_vaultRootPath == null) return;
    if (!_pagePaths.containsKey(pageId)) return;

    final buffer = _buffers.putIfAbsent(pageId, _ActionBuffer.new);

    if (_tryAccumulate(buffer, action)) {
      buffer.timer?.cancel();
      buffer.timer = Timer(
        const Duration(milliseconds: 250),
        () => _flushBuffer(pageId),
      );
      return;
    }

    _flushBufferSync(pageId);
    buffer.pending = action;
    buffer.timer?.cancel();
    buffer.timer = Timer(
      const Duration(milliseconds: 250),
      () => _flushBuffer(pageId),
    );
  }

  Future<void> flush(String pageId) => _flushBuffer(pageId);

  Future<void> clear(String pageId) async {
    _buffers.remove(pageId)?.timer?.cancel();
    final relativePath = _pagePaths[pageId];
    if (relativePath == null) return;

    final walPath = _absoluteWalPath(relativePath);
    if (await _fs.fileExists(walPath)) {
      await _fs.deleteFile(walPath);
    }
  }

  Future<void> clearAll() async {
    if (_vaultRootPath == null) return;
    for (final buffer in _buffers.values) {
      buffer.timer?.cancel();
    }
    _buffers.clear();

    try {
      final walDir = '$_vaultRootPath/.noetec/wal';
      if (!await _fs.directoryExists(walDir)) return;
      final filePaths = await _findWalFilePaths(walDir);
      for (final path in filePaths) {
        await _fs.deleteFile(path);
      }
    } catch (_) {}
  }

  Future<List<WalEntry>> getPendingWals() async {
    if (_vaultRootPath == null) return const [];
    final entries = <WalEntry>[];
    final walDir = '$_vaultRootPath/.noetec/wal';

    try {
      if (!await _fs.directoryExists(walDir)) return entries;
      final filePaths = await _findWalFilePaths(walDir);
      for (final filePath in filePaths) {
        try {
          final raw = await _fs.readFile(filePath);
          final lines = raw
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList();
          if (lines.isEmpty) continue;

          final relativePath = _extractRelativePathFromWal(filePath);
          entries.add(
            WalEntry(
              relativePath: relativePath,
              walFilePath: filePath,
              actionCount: lines.length,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}

    return entries;
  }

  Future<List<String>> _findWalFilePaths(String dirPath) async {
    final results = <String>[];
    final entries = await _fs.listDirectory(dirPath);
    for (final entry in entries) {
      if (entry.isDirectory) {
        results.addAll(await _findWalFilePaths(entry.path));
      } else {
        results.add(entry.path);
      }
    }
    return results;
  }

  String _extractRelativePathFromWal(String walFilePath) {
    return walFilePath
        .replaceAll('\\', '/')
        .replaceFirst('$_vaultRootPath/.noetec/wal/', '');
  }

  Future<List<PageEditAction>> readWal(String walFilePath) async {
    if (!await _fs.fileExists(walFilePath)) return const [];

    final raw = await _fs.readFile(walFilePath);
    final actions = <PageEditAction>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      json.remove('ts');
      json.remove('count');
      actions.add(_serializer.fromJson(json));
    }
    return actions;
  }

  bool _tryAccumulate(_ActionBuffer buffer, PageEditAction action) {
    final pending = buffer.pending;
    if (pending == null) {
      buffer.pending = action;
      return true;
    }

    if (pending is InsertTextAction && action is InsertTextAction) {
      if (pending.blockId == action.blockId &&
          pending.flatOffset + pending.text.length == action.flatOffset) {
        buffer.pending = InsertTextAction(
          blockId: pending.blockId,
          flatOffset: pending.flatOffset,
          text: pending.text + action.text,
        );
        return true;
      }
    }

    if (pending is DeleteTextBackAction && action is DeleteTextBackAction) {
      if (pending.blockId == action.blockId &&
          action.flatOffset == pending.flatOffset - 1) {
        buffer.pending = action;
        buffer.deleteBackCount += 1;
        return true;
      }
    }

    if (pending is DeleteTextForwardAction &&
        action is DeleteTextForwardAction) {
      if (pending.blockId == action.blockId &&
          action.flatOffset == pending.flatOffset) {
        buffer.deleteForwardCount += 1;
        return true;
      }
    }

    return false;
  }

  Future<void> _flushBuffer(String pageId) async {
    if (_vaultRootPath == null) return;
    final buffer = _buffers[pageId];
    if (buffer == null || buffer.pending == null) return;

    final action = buffer.pending!;
    final deleteBackCount = buffer.deleteBackCount;
    final deleteForwardCount = buffer.deleteForwardCount;

    buffer.pending = null;
    buffer.timer?.cancel();
    buffer.timer = null;
    buffer.deleteBackCount = 0;
    buffer.deleteForwardCount = 0;

    final relativePath = _pagePaths[pageId];
    if (relativePath == null) return;

    final json = _serializer.toJson(action);
    json['ts'] = DateTime.now().millisecondsSinceEpoch;

    if (action is DeleteTextBackAction && deleteBackCount > 0) {
      json['count'] = deleteBackCount + 1;
    }
    if (action is DeleteTextForwardAction && deleteForwardCount > 0) {
      json['count'] = deleteForwardCount + 1;
    }

    final walPath = _absoluteWalPath(relativePath);
    final parentDir = walPath.substring(0, walPath.lastIndexOf('/'));
    if (!await _fs.directoryExists(parentDir)) {
      await _fs.createDirectory(parentDir);
    }
    await _fs.appendToFile(walPath, '${jsonEncode(json)}\n');
  }

  void _flushBufferSync(String pageId) => _flushBuffer(pageId);

  String _absoluteWalPath(String relativePath) {
    return '$_vaultRootPath/.noetec/wal/$relativePath';
  }

  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    deactivate();
  }
}

class _ActionBuffer {
  PageEditAction? pending;
  Timer? timer;
  int deleteBackCount = 0;
  int deleteForwardCount = 0;
}
