// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/settings_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';

class FakeSettingsService implements ISettingsService {
  final Map<String, String> _stringStore = {};
  final Map<String, List<String>> _listStore = {};

  @override
  Future<String?> getString(String key) async => _stringStore[key];

  @override
  Future<void> setString(String key, String value) async =>
      _stringStore[key] = value;

  @override
  Future<List<String>> getStringList(String key) async => _listStore[key] ?? [];

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _listStore[key] = value;
}

void main() {
  group('VaultRepository —', () {
    late FakeSettingsService fakeSettings;
    late VaultRepositoryImpl repository;

    final fixedDate = DateTime.utc(2026, 1, 15, 12, 0, 0);

    VaultEntity makeVault({
      String id = 'vault-1',
      String name = 'Test Vault',
      String rootPath = '/path/to/vault',
    }) {
      return VaultEntity(
        id: id,
        name: name,
        rootPath: rootPath,
        createdAt: fixedDate,
      );
    }

    setUp(() {
      fakeSettings = FakeSettingsService();
      repository = VaultRepositoryImpl(fakeSettings);
    });

    test('addToRecent — adds vault and loadRecentVaults returns it', () async {
      final vault = makeVault();
      await repository.addToRecent(vault);

      final result = await repository.loadRecentVaults();
      expect(result, hasLength(1));
      expect(result.first, equals(vault));
    });

    test('addToRecent — moves existing vault to top', () async {
      final vault1 = makeVault(id: 'vault-1', name: 'First');
      final vault2 = makeVault(id: 'vault-2', name: 'Second');

      await repository.addToRecent(vault1);
      await repository.addToRecent(vault2);
      await repository.addToRecent(vault1);

      final result = await repository.loadRecentVaults();
      expect(result, hasLength(2));
      expect(result.first.id, equals('vault-1'));
      expect(result.last.id, equals('vault-2'));
    });

    test('removeFromRecent — removes vault from list', () async {
      final vault1 = makeVault(id: 'vault-1');
      final vault2 = makeVault(id: 'vault-2');

      await repository.addToRecent(vault1);
      await repository.addToRecent(vault2);
      await repository.removeFromRecent('vault-1');

      final result = await repository.loadRecentVaults();
      expect(result, hasLength(1));
      expect(result.first.id, equals('vault-2'));
    });
  });
}
