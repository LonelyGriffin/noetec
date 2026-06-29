// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';
import 'package:noetec/systems/sync_system/conflict_store.dart';
import 'package:noetec/systems/sync_system/external_edit_handler.dart';
import 'package:noetec/systems/sync_system/merge_applier.dart';
import 'package:noetec/systems/sync_system/merge_engine.dart';
import 'package:noetec/systems/sync_system/sync_watcher.dart';
import 'package:noetec/systems/sync_system/vault_watcher.dart';
import 'package:noetec/systems/vault/vault_system.dart';

enum SyncStatus { idle, checking, merging, conflict, error }

enum DocumentSyncState { synced, pending, merging, conflict }

class SyncSystem {
  SyncSystem({
    required OpLogSystem oplogSystem,
    required IFileSystemService fileSystem,
    required MarkdownSystem markdownSystem,
    required VaultSystem vaultSystem,
    required IDeviceService deviceService,
  }) : _oplogSystem = oplogSystem,
       _fileSystem = fileSystem,
       _markdownSystem = markdownSystem,
       _vaultSystem = vaultSystem,
       _deviceService = deviceService {
    _conflictStore = ConflictStore(fileSystem);
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final OpLogSystem _oplogSystem;
  final IFileSystemService _fileSystem;
  final MarkdownSystem _markdownSystem;
  final VaultSystem _vaultSystem;
  final IDeviceService _deviceService;

  String? _vaultRootPath;
  String? _ownDeviceUuid;

  late SyncWatcher _syncWatcher;
  late VaultWatcher _vaultWatcher;
  late MergeApplier _mergeApplier;
  late ExternalEditHandler _externalEditHandler;
  late final ConflictStore _conflictStore;

  StreamSubscription<SyncChangeEvent>? _syncSubscription;
  StreamSubscription<ExternalEditEvent>? _externalEditSubscription;

  final Map<String, DocumentSyncState> _documentStates = {};
  final status = ValueNotifier<SyncStatus>(SyncStatus.idle);

  ConflictStore get conflictStore => _conflictStore;

  DocumentSyncState documentStateOf(String relativePath) =>
      _documentStates[relativePath] ?? DocumentSyncState.synced;

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      final device = _deviceService.currentDevice;
      if (device == null) return;
      _vaultRootPath = vault.rootPath;
      _ownDeviceUuid = device.uuid;
      _syncWatcher = SyncWatcher(
        fileSystem: _fileSystem,
        vaultRootPath: _vaultRootPath!,
        ownDeviceUuid: _ownDeviceUuid!,
      );
      _vaultWatcher = VaultWatcher(
        fileSystem: _fileSystem,
        vaultRootPath: _vaultRootPath!,
      );
      _mergeApplier = MergeApplier(
        fileSystem: _fileSystem,
        markdownSystem: _markdownSystem,
        vaultRootPath: _vaultRootPath!,
      );
      _externalEditHandler = ExternalEditHandler(
        fileSystem: _fileSystem,
        markdownSystem: _markdownSystem,
        oplogSystem: _oplogSystem,
        vaultRootPath: _vaultRootPath!,
      );
      unawaited(start());
    } else {
      stop();
      _vaultRootPath = null;
      _ownDeviceUuid = null;
      _documentStates.clear();
    }
  }

  Future<void> start() async {
    if (_vaultRootPath == null) return;
    await _conflictStore.load(_vaultRootPath!);
    await checkAll();
    _syncWatcher.start();
    _vaultWatcher.start();

    _syncSubscription = _syncWatcher.events.listen(_onSyncChange);
    _externalEditSubscription = _vaultWatcher.events.listen(_onExternalEdit);
  }

  void stop() {
    _syncWatcher.stop();
    _vaultWatcher.stop();
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _externalEditSubscription?.cancel();
    _externalEditSubscription = null;
  }

  Future<void> checkAll() async {
    if (_vaultRootPath == null) return;
    final syncPagesDir = '$_vaultRootPath/.sync/pages';
    if (!await _fileSystem.directoryExists(syncPagesDir)) return;

    final entries = await _fileSystem.listDirectory(syncPagesDir);
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final encoded = entry.name;
      try {
        final relativePath = Uri.decodeComponent(encoded);
        await checkFile(relativePath);
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> checkFile(String relativePath) async {
    if (_conflictStore.hasConflicts(relativePath)) {
      _documentStates[relativePath] = DocumentSyncState.conflict;
      status.value = SyncStatus.conflict;
      return;
    }

    _documentStates[relativePath] = DocumentSyncState.pending;
    status.value = SyncStatus.checking;

    try {
      final dag = await _oplogSystem.buildDag(relativePath);
      final topology = dag.topology;

      if (topology == DagTopology.empty || topology == DagTopology.single) {
        _documentStates[relativePath] = DocumentSyncState.synced;
        status.value = SyncStatus.idle;
        return;
      }

      _documentStates[relativePath] = DocumentSyncState.merging;
      status.value = SyncStatus.merging;

      final result = MergeEngine.merge(dag);
      await _applyMergeResult(relativePath, result);
    } catch (exception) {
      _documentStates[relativePath] = DocumentSyncState.synced;
      status.value = SyncStatus.error;
    }
  }

  Future<void> _onSyncChange(SyncChangeEvent event) async {
    await checkFile(event.relativePath);
  }

  Future<void> _onExternalEdit(ExternalEditEvent event) async {
    final pageId = await _externalEditHandler.handleExternalEdit(
      event.relativePath,
      null,
    );
    _vaultWatcher.acknowledge(event.relativePath);
    if (pageId != null) {
      await checkFile(event.relativePath);
    }
  }

  Future<void> _applyMergeResult(
    String relativePath,
    MergeResult result,
  ) async {
    if (_vaultRootPath == null) return;
    switch (result) {
      case MergeNoop():
        _documentStates[relativePath] = DocumentSyncState.synced;
        status.value = _hasAnyConflict()
            ? SyncStatus.conflict
            : SyncStatus.idle;

      case MergeFastForward():
        await _writeMergedBlocks(relativePath, result.updatedBlocks);
        _documentStates[relativePath] = DocumentSyncState.synced;
        status.value = _hasAnyConflict()
            ? SyncStatus.conflict
            : SyncStatus.idle;

      case MergeSuccess():
        await _writeMergedBlocks(relativePath, result.mergedBlocks);
        await _recordMergeEntry(relativePath, result.ourHead, result.theirHead);
        _documentStates[relativePath] = DocumentSyncState.synced;
        status.value = _hasAnyConflict()
            ? SyncStatus.conflict
            : SyncStatus.idle;

      case MergeConflict():
        await _writeMergedBlocks(relativePath, result.partiallyMergedBlocks);
        _conflictStore.addConflicts(
          relativePath,
          result.conflicts,
          result.ourHead,
          result.theirHead,
        );
        await _conflictStore.save(_vaultRootPath!);
        _documentStates[relativePath] = DocumentSyncState.conflict;
        status.value = SyncStatus.conflict;
        await _recordMergeEntry(relativePath, result.ourHead, result.theirHead);
    }
  }

  Future<({String fileHash, String content})> _writeMergedBlocks(
    String relativePath,
    List<ReconstructedBlock> blocks,
  ) async {
    return _mergeApplier.applyToDisk(relativePath, blocks);
  }

  Future<void> _recordMergeEntry(
    String relativePath,
    Hlc hlcA,
    Hlc hlcB,
  ) async {
    await _oplogSystem.recordMerge(relativePath, hlcA, hlcB, '');
  }

  bool _hasAnyConflict() => _conflictStore.isNotEmpty;

  void acknowledgeSyncChange(String path) {
    _syncWatcher.acknowledge(path);
  }

  void acknowledgeExternalEdit(String path) {
    _vaultWatcher.acknowledge(path);
  }

  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    stop();
    if (_vaultRootPath != null) {
      _conflictStore.save(_vaultRootPath!);
    }
    status.dispose();
  }
}
