// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/user_service.dart';
import '../../helpers/test_fakes.dart';

void main() {
  late FakeFileSystemService fs;
  late FakeSecureKeyStore keyStore;
  late UserServiceImpl service;

  const vaultRoot = '/vault';
  const vaultId = 'vault-1';
  const identityPath = '/vault/.noetec/identity.json';

  UserServiceImpl buildService(FakeFileSystemService f, FakeSecureKeyStore k) => UserServiceImpl(f, FakeIdService(), CryptoServiceImpl(), k);

  setUp(() {
    fs = FakeFileSystemService();
    keyStore = FakeSecureKeyStore();
    service = buildService(fs, keyStore);
  });

  group('UserServiceImpl —', () {
    test('createIdentity writes identity.json with only public fields', () async {
      final created = await service.createIdentity(vaultRoot, vaultId);

      expect(fs.files[identityPath], isNotNull);
      final json = jsonDecode(fs.files[identityPath]!) as Map<String, dynamic>;
      expect(json.keys.toSet(), {'userId', 'name', 'publicKey', 'role'});
      expect(json['role'], 'owner');
      // No private material on disk.
      expect(json.toString(), isNot(contains('seed')));
      expect(created.identity.publicKey, json['publicKey']);
    });

    test('createIdentity stores seed and private key only in secure storage', () async {
      await service.createIdentity(vaultRoot, vaultId);

      expect(await keyStore.readIdentitySeed(vaultId), isNotNull);
      expect(await keyStore.readIdentityPrivateKey(vaultId), isNotNull);
      // The seed round-trips back to 32 bytes.
      final seedB64 = await keyStore.readIdentitySeed(vaultId);
      expect(seedB64, isNotNull);
      final padded = seedB64!.padRight((seedB64.length + 3) ~/ 4 * 4, '=');
      expect(base64Url.decode(padded).length, 32);
    });

    test('createIdentity exposes a 24-word mnemonic that validates', () async {
      final created = await service.createIdentity(vaultRoot, vaultId);
      final words = created.mnemonic.split(' ');
      expect(words.length, 24);
      expect(bip39.validateMnemonic(created.mnemonic), isTrue);
    });

    test('restoreIdentity from the creation mnemonic yields the SAME identity', () async {
      final created = await service.createIdentity(vaultRoot, vaultId);

      // Simulate a fresh device: new file system + new key store.
      final fs2 = FakeFileSystemService();
      final keyStore2 = FakeSecureKeyStore();
      final fresh = buildService(fs2, keyStore2);

      final restored = await fresh.restoreIdentity(vaultRoot, vaultId, created.mnemonic);

      expect(restored.publicKey, created.identity.publicKey);
      expect(fs2.files[identityPath], isNotNull);
      // Secrets were re-derived on the new device.
      expect(await keyStore2.readIdentitySeed(vaultId), isNotNull);
    });

    test('restoreIdentity is deterministic across calls', () async {
      final a = await service.createIdentity(vaultRoot, vaultId);
      final b = await service.restoreIdentity(vaultRoot, vaultId, a.mnemonic);
      expect(b.publicKey, a.identity.publicKey);
    });

    test('restoreIdentity rejects an invalid mnemonic', () async {
      expect(() => service.restoreIdentity(vaultRoot, vaultId, 'not a valid mnemonic at all'), throwsArgumentError);
    });

    test('loadIdentity returns null when identity.json is absent', () async {
      expect(await service.loadIdentity(vaultRoot), isNull);
    });

    test('loadIdentity reads an existing identity.json', () async {
      await service.createIdentity(vaultRoot, vaultId, name: 'Bob');
      final loaded = await service.loadIdentity(vaultRoot);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Bob');
      expect(loaded.role, 'owner');
      expect(service.currentIdentity, isNotNull);
    });

    test('loadIdentity sets currentIdentity from a clean state', () async {
      // Write identity.json with one service instance.
      await service.createIdentity(vaultRoot, vaultId, name: 'Carol');

      // A brand-new service (no prior create) starts with null state.
      final fresh = buildService(fs, keyStore);
      expect(fresh.currentIdentity, isNull);

      final loaded = await fresh.loadIdentity(vaultRoot);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Carol');
      expect(fresh.currentIdentity, isNotNull);
      expect(fresh.currentIdentity!.publicKey, loaded.publicKey);
    });

    test('clear() drops the in-memory identity', () async {
      await service.createIdentity(vaultRoot, vaultId);
      expect(service.currentIdentity, isNotNull);
      service.clear();
      expect(service.currentIdentity, isNull);
    });
  });
}
