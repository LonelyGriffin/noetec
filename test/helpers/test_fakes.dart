import 'dart:async';

import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:noetec/systems/vault/vault_system.dart';

class FakeIdService implements IIdService {
  int _counter = 0;
  @override
  String generateId() => 'test-id-${_counter++}';
}

class FakeFileSystemService implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> dirs = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readFile(String path) async => files[path] ?? '';
  @override
  Future<void> writeFile(String path, String content) async =>
      files[path] = content;
  @override
  Future<void> appendToFile(String path, String content) async =>
      files[path] = (files[path] ?? '') + content;
  @override
  Future<void> deleteFile(String path) async => files.remove(path);
  @override
  Future<bool> directoryExists(String path) async => dirs.contains(path);
  @override
  Future<void> createDirectory(String path) async => dirs.add(path);
  @override
  Future<String?> pickDirectory() async => null;
  @override
  Future<List<FileEntry>> listDirectory(String path) async => [];
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}
  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();
}

class FakeVaultRepository implements IVaultRepository {
  @override
  Future<List<VaultEntity>> loadRecentVaults() async => [];
  @override
  Future<void> saveRecentVaults(List<VaultEntity> vaults) async {}
  @override
  Future<void> addToRecent(VaultEntity vault) async {}
  @override
  Future<void> removeFromRecent(String vaultId) async {}
}

class FakeDeviceService implements IDeviceService {
  DeviceIdentity? _device;

  void setDevice(DeviceIdentity? device) => _device = device;

  @override
  DeviceIdentity? get currentDevice => _device;

  @override
  Future<DeviceIdentity> ensureDevice(
    String vaultRootPath,
    String vaultId,
  ) async {
    _device ??= DeviceIdentity(
      uuid: 'test-device-uuid',
      name: 'Test Device',
      createdAt: DateTime.now(),
      lastHlc: null,
      publicKey: 'test-public-key',
    );
    return _device!;
  }

  @override
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey) async {
    if (_device != null) {
      _device = _device!.withLastHlc(hlcKey);
    }
  }

  @override
  void clear() => _device = null;
}

VaultSystem createTestVaultSystem({
  IFileSystemService? fileSystem,
  IVaultRepository? repository,
  IIdService? idService,
  IDeviceService? deviceService,
}) {
  return VaultSystem(
    fileSystem ?? FakeFileSystemService(),
    repository ?? FakeVaultRepository(),
    idService ?? FakeIdService(),
    deviceService ?? FakeDeviceService(),
  );
}
