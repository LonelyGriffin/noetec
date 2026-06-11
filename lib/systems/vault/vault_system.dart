// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';
import 'dart:convert';

import 'package:command_it/command_it.dart';
import 'package:noetec/entity/vault/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:path/path.dart' as p;

class VaultAlreadyExistsException implements Exception {
  VaultAlreadyExistsException(this.path);

  final String path;

  @override
  String toString() =>
      'VaultAlreadyExistsException: vault already exists at $path';
}

class DirectoryAlreadyExistsException implements Exception {
  DirectoryAlreadyExistsException(this.existingPath);

  final String existingPath;

  @override
  String toString() =>
      'DirectoryAlreadyExistsException: directory already exists at $existingPath';
}

class InvalidVaultException implements Exception {
  InvalidVaultException(this.path);

  final String path;

  @override
  String toString() => 'InvalidVaultException: no valid vault found at $path';
}

class VaultSystem {
  VaultSystem(this._fileSystem, this._repository, this._ids);

  final IFileSystemService _fileSystem;
  final IVaultRepository _repository;
  final IIdService _ids;

  final currentVault = CustomValueNotifier<VaultEntity?>(null);
  final recentVaults = ListNotifier<VaultEntity>();

  late final createVaultCommand =
      Command.createAsync<
        ({String parentPath, String vaultName}),
        VaultEntity?
      >(_createVault, initialValue: null, debugName: 'createVault');

  late final openVaultCommand = Command.createAsync<String, VaultEntity?>(
    _openVault,
    initialValue: null,
    debugName: 'openVault',
  );

  late final closeVaultCommand = Command.createSyncNoParamNoResult(
    _closeVault,
    debugName: 'closeVault',
  );

  Future<void> init() async {
    final vaults = await _repository.loadRecentVaults();
    recentVaults
      ..clear()
      ..addAll(vaults);
  }

  Future<VaultEntity?> _createVault(
    ({String parentPath, String vaultName}) params,
  ) async {
    final directoryPath = p.join(params.parentPath, params.vaultName);

    if (await _fileSystem.directoryExists(directoryPath)) {
      throw DirectoryAlreadyExistsException(directoryPath);
    }

    final noetecDir = p.join(directoryPath, '.noetec');
    await _fileSystem.createDirectory(noetecDir);

    final vault = VaultEntity(
      id: _ids.generateId(),
      name: params.vaultName,
      rootPath: directoryPath,
      createdAt: DateTime.now(),
    );

    final vaultFile = p.join(noetecDir, 'vault.json');
    final content = json.encode(vault.toMap());
    await _fileSystem.writeFile(vaultFile, content);

    currentVault.value = vault;
    await _repository.addToRecent(vault);
    unawaited(_syncRecentVaults());

    return vault;
  }

  Future<VaultEntity?> _openVault(String directoryPath) async {
    final vaultFile = p.join(directoryPath, '.noetec', 'vault.json');

    if (!await _fileSystem.fileExists(vaultFile)) {
      throw InvalidVaultException(directoryPath);
    }

    final content = await _fileSystem.readFile(vaultFile);
    final data = json.decode(content) as Map<String, dynamic>;
    final vault = VaultEntity.fromMap(data);

    currentVault.value = vault;
    await _repository.addToRecent(vault);
    unawaited(_syncRecentVaults());

    return vault;
  }

  void _closeVault() {
    currentVault.value = null;
  }

  Future<void> _syncRecentVaults() async {
    final vaults = await _repository.loadRecentVaults();
    recentVaults
      ..clear()
      ..addAll(vaults);
  }

  void dispose() {
    currentVault.dispose();
    recentVaults.dispose();
    createVaultCommand.dispose();
    openVaultCommand.dispose();
    closeVaultCommand.dispose();
  }
}
