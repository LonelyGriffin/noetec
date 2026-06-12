// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/settings_service.dart';

abstract interface class IVaultRepository {
  Future<List<VaultEntity>> loadRecentVaults();

  Future<void> saveRecentVaults(List<VaultEntity> vaults);

  Future<void> addToRecent(VaultEntity vault);

  Future<void> removeFromRecent(String vaultId);
}

class VaultRepositoryImpl implements IVaultRepository {
  VaultRepositoryImpl(this._settings);

  final ISettingsService _settings;

  static const _storageKey = 'noetec.recent_vaults';

  @override
  Future<List<VaultEntity>> loadRecentVaults() async {
    final raw = await _settings.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => VaultEntity.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveRecentVaults(List<VaultEntity> vaults) async {
    final encoded = json.encode(vaults.map((vault) => vault.toMap()).toList());
    await _settings.setString(_storageKey, encoded);
  }

  @override
  Future<void> addToRecent(VaultEntity vault) async {
    final current = await loadRecentVaults();
    current.removeWhere((existing) => existing.id == vault.id);
    current.insert(0, vault);
    await saveRecentVaults(current);
  }

  @override
  Future<void> removeFromRecent(String vaultId) async {
    final current = await loadRecentVaults();
    current.removeWhere((existing) => existing.id == vaultId);
    await saveRecentVaults(current);
  }
}
