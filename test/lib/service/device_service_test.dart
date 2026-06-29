import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/secure_key_store.dart';

class FakeFileSystemService implements IFileSystemService {
  final Map<String, String> files = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readFile(String path) async => files[path]!;
  @override
  Future<void> writeFile(String path, String content) async =>
      files[path] = content;
  @override
  Future<bool> directoryExists(String path) async => true;
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<String?> pickDirectory() async => null;
  @override
  Future<List<FileEntry>> listDirectory(String path) async => [];
  @override
  Future<void> deleteFile(String path) async => files.remove(path);
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}
  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();
  @override
  Future<void> appendToFile(String path, String content) async {
    files[path] = (files[path] ?? '') + content;
  }
}

class FakeIdService implements IIdService {
  @override
  String generateId() => 'fixed-device-uuid';
}

class FakeCryptoService implements ICryptoService {
  @override
  Future<({String publicKeyBase64, String privateKeyBase64})>
  generateDeviceKeyPair() async {
    return (
      publicKeyBase64: 'fake-public-key-base64',
      privateKeyBase64: 'fake-private-key-base64',
    );
  }
}

class FakeSecureKeyStore implements ISecureKeyStore {
  final Map<String, String> _store = {};

  @override
  Future<void> storeDevicePrivateKey(
    String vaultId,
    String devicePrivateKeyBase64,
  ) async {
    _store[vaultId] = devicePrivateKeyBase64;
  }

  @override
  Future<String?> readDevicePrivateKey(String vaultId) async => _store[vaultId];

  @override
  Future<bool> hasDevicePrivateKey(String vaultId) async =>
      _store.containsKey(vaultId);

  @override
  Future<void> deleteDevicePrivateKey(String vaultId) async =>
      _store.remove(vaultId);
}

void main() {
  group('DeviceService —', () {
    late FakeFileSystemService fs;
    late FakeSecureKeyStore secureKeyStore;
    late DeviceServiceImpl service;

    setUp(() {
      fs = FakeFileSystemService();
      secureKeyStore = FakeSecureKeyStore();
      service = DeviceServiceImpl(
        fs,
        FakeIdService(),
        FakeCryptoService(),
        secureKeyStore,
      );
    });

    test('ensureDevice creates device.json when not exists', () async {
      final device = await service.ensureDevice('/vault', 'vault-id-1');

      expect(device.uuid, 'fixed-device-uuid');
      expect(device.lastHlc, isNull);
      expect(device.publicKey, isNotNull);
      expect(fs.files.containsKey('/vault/.noetec/device.json'), isTrue);
    });

    test('ensureDevice generates key pair for new device', () async {
      final device = await service.ensureDevice('/vault', 'vault-id-keys');

      expect(device.publicKey, 'fake-public-key-base64');
      expect(
        await secureKeyStore.readDevicePrivateKey('vault-id-keys'),
        'fake-private-key-base64',
      );
    });

    test('ensureDevice reads existing device.json', () async {
      final existing = DeviceIdentity(
        uuid: 'existing-uuid',
        name: 'Existing',
        createdAt: DateTime(2026, 1, 1),
        lastHlc: null,
        publicKey: 'existing-public-key',
      );
      fs.files['/vault/.noetec/device.json'] = jsonEncode(existing.toJson());

      final device = await service.ensureDevice('/vault', 'vault-id-2');
      expect(device.uuid, 'existing-uuid');
      expect(device.publicKey, 'existing-public-key');
    });

    test('ensureDevice does not regenerate keys for existing device', () async {
      final existing = DeviceIdentity(
        uuid: 'existing-uuid',
        name: 'Existing',
        createdAt: DateTime(2026, 1, 1),
        lastHlc: null,
        publicKey: 'original-public-key',
      );
      fs.files['/vault/.noetec/device.json'] = jsonEncode(existing.toJson());

      await service.ensureDevice('/vault', 'vault-id-no-regen');

      expect(
        await secureKeyStore.hasDevicePrivateKey('vault-id-no-regen'),
        isFalse,
      );
    });

    test('updateLastHlc persists updated lastHlc', () async {
      await service.ensureDevice('/vault', 'vault-id-3');
      await service.updateLastHlc('/vault', '1705312200000-0001-a1b2c3d4');

      final content =
          jsonDecode(fs.files['/vault/.noetec/device.json']!)
              as Map<String, dynamic>;
      expect(content['last_hlc'], '1705312200000-0001-a1b2c3d4');
    });
  });
}
