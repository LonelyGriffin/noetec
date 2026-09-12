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

  /// Renames the local device in `.noetec/device.json` and updates the
  /// in-memory [currentDevice]. The device's `lastHlc` is preserved.
  ///
  /// The display name is a local label only (it does not rebind the device
  /// certificate in the synced registry — renaming the device in the
  /// `devices/<userId>.json` certificate is a separate registry operation).
  Future<DeviceIdentity> renameDevice(String vaultRootPath, String newName);
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey);
  void clear();
}

class DeviceServiceImpl implements IDeviceService {
  final IFileSystemService _fileSystem;
  final IIdService _idService;
  final ICryptoService _cryptoService;
  final ISecureKeyStore _secureKeyStore;
  DeviceIdentity? _currentDevice;

  DeviceServiceImpl(this._fileSystem, this._idService, this._cryptoService, this._secureKeyStore);

  @override
  DeviceIdentity? get currentDevice => _currentDevice;

  @override
  Future<DeviceIdentity> ensureDevice(String vaultRootPath, String vaultId) async {
    final devicePath = '$vaultRootPath/.noetec/device.json';
    if (await _fileSystem.fileExists(devicePath)) {
      final content = await _fileSystem.readFile(devicePath);
      _currentDevice = DeviceIdentity.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } else {
      final keyPair = await _cryptoService.generateDeviceKeyPair();

      _currentDevice = DeviceIdentity(uuid: _idService.generateId(), name: 'Default Device', createdAt: DateTime.now(), lastHlc: null, publicKey: keyPair.publicKeyBase64Url);
      await _fileSystem.writeFile(devicePath, jsonEncode(_currentDevice!.toJson()));
      await _secureKeyStore.storeDevicePrivateKey(vaultId, keyPair.privateKeyBase64Url);
    }
    return _currentDevice!;
  }

  @override
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey) async {
    if (_currentDevice == null) return;
    _currentDevice = _currentDevice!.withLastHlc(hlcKey);
    final devicePath = '$vaultRootPath/.noetec/device.json';
    await _fileSystem.writeFile(devicePath, jsonEncode(_currentDevice!.toJson()));
  }

  @override
  Future<DeviceIdentity> renameDevice(String vaultRootPath, String newName) async {
    final device = _currentDevice;
    if (device == null) {
      throw StateError('no local device to rename (call ensureDevice first)');
    }
    final renamed = device.withName(newName);
    _currentDevice = renamed;
    final devicePath = '$vaultRootPath/.noetec/device.json';
    await _fileSystem.writeFile(devicePath, jsonEncode(renamed.toJson()));
    return renamed;
  }

  @override
  void clear() {
    _currentDevice = null;
  }
}
