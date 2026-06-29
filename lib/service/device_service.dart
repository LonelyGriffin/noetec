// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import '../entity/device/device_identity.dart';
import 'crypto_service.dart';
import 'file_system_service.dart';
import 'id_service.dart';
import 'secure_key_store.dart';

abstract interface class IDeviceService {
  DeviceIdentity? get currentDevice;
  Future<DeviceIdentity> ensureDevice(String vaultRootPath, String vaultId);
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey);
  void clear();
}

class DeviceServiceImpl implements IDeviceService {
  final IFileSystemService _fileSystem;
  final IIdService _idService;
  final ICryptoService _cryptoService;
  final ISecureKeyStore _secureKeyStore;
  DeviceIdentity? _currentDevice;

  DeviceServiceImpl(
    this._fileSystem,
    this._idService,
    this._cryptoService,
    this._secureKeyStore,
  );

  @override
  DeviceIdentity? get currentDevice => _currentDevice;

  @override
  Future<DeviceIdentity> ensureDevice(
    String vaultRootPath,
    String vaultId,
  ) async {
    final devicePath = '$vaultRootPath/.noetec/device.json';
    if (await _fileSystem.fileExists(devicePath)) {
      final content = await _fileSystem.readFile(devicePath);
      _currentDevice = DeviceIdentity.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
    } else {
      final keyPair = await _cryptoService.generateDeviceKeyPair();

      _currentDevice = DeviceIdentity(
        uuid: _idService.generateId(),
        name: 'Default Device',
        createdAt: DateTime.now(),
        lastHlc: null,
        publicKey: keyPair.publicKeyBase64,
      );
      await _fileSystem.writeFile(
        devicePath,
        jsonEncode(_currentDevice!.toJson()),
      );
      await _secureKeyStore.storeDevicePrivateKey(
        vaultId,
        keyPair.privateKeyBase64,
      );
    }
    return _currentDevice!;
  }

  @override
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey) async {
    if (_currentDevice == null) return;
    _currentDevice = _currentDevice!.withLastHlc(hlcKey);
    final devicePath = '$vaultRootPath/.noetec/device.json';
    await _fileSystem.writeFile(
      devicePath,
      jsonEncode(_currentDevice!.toJson()),
    );
  }

  @override
  void clear() {
    _currentDevice = null;
  }
}
