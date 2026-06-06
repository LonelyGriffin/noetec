// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/vault/vault.dart';

void main() {
  group('VaultEntity —', () {
    final fixedDate = DateTime.utc(2026, 1, 15, 12, 0, 0);

    VaultEntity makeVault({
      String id = 'vault-1',
      String name = 'Test Vault',
      String rootPath = '/path/to/vault',
      DateTime? createdAt,
    }) {
      return VaultEntity(
        id: id,
        name: name,
        rootPath: rootPath,
        createdAt: createdAt ?? fixedDate,
      );
    }

    test('toMap / fromMap — roundtrip preserves all fields', () {
      final original = makeVault();
      final restored = VaultEntity.fromMap(original.toMap());

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.rootPath, equals(original.rootPath));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored, equals(original));
    });

    test('rename — creates new object with updated name', () {
      final original = makeVault();
      final renamed = original.rename('New Name');

      expect(renamed.name, equals('New Name'));
      expect(renamed.id, equals(original.id));
      expect(renamed.rootPath, equals(original.rootPath));
      expect(renamed.createdAt, equals(original.createdAt));
      expect(renamed, isNot(equals(original)));
    });

    test('relocate — creates new object with updated rootPath', () {
      final original = makeVault();
      final relocated = original.relocate('/new/path');

      expect(relocated.rootPath, equals('/new/path'));
      expect(relocated.id, equals(original.id));
      expect(relocated.name, equals(original.name));
      expect(relocated.createdAt, equals(original.createdAt));
      expect(relocated, isNot(equals(original)));
    });

    test('withUpdate — applies only specified fields', () {
      final original = makeVault();
      final updated = original.withUpdate(name: 'Updated');

      expect(updated.name, equals('Updated'));
      expect(updated.rootPath, equals(original.rootPath));
      expect(updated.id, equals(original.id));
    });

    test('== and hashCode — equal objects have same hashCode', () {
      final vault1 = makeVault();
      final vault2 = makeVault();

      expect(vault1, equals(vault2));
      expect(vault1.hashCode, equals(vault2.hashCode));
    });

    test('== and hashCode — different objects are not equal', () {
      final vault1 = makeVault(id: 'vault-1');
      final vault2 = makeVault(id: 'vault-2');

      expect(vault1, isNot(equals(vault2)));
    });
  });
}
