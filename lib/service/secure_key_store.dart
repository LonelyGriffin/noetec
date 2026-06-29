// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ISecureKeyStore {
  Future<void> storeDevicePrivateKey(
    String vaultId,
    String devicePrivateKeyBase64,
  );
  Future<String?> readDevicePrivateKey(String vaultId);
  Future<bool> hasDevicePrivateKey(String vaultId);
  Future<void> deleteDevicePrivateKey(String vaultId);
}

class SecureKeyStoreImpl implements ISecureKeyStore {
  SecureKeyStoreImpl({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _storageKey(String vaultId) {
    return 'noetec.device_private_key.$vaultId';
  }

  @override
  Future<void> storeDevicePrivateKey(
    String vaultId,
    String devicePrivateKeyBase64,
  ) async {
    await _storage.write(
      key: _storageKey(vaultId),
      value: devicePrivateKeyBase64,
    );
  }

  @override
  Future<String?> readDevicePrivateKey(String vaultId) async {
    return _storage.read(key: _storageKey(vaultId));
  }

  @override
  Future<bool> hasDevicePrivateKey(String vaultId) async {
    final value = await _storage.read(key: _storageKey(vaultId));
    return value != null;
  }

  @override
  Future<void> deleteDevicePrivateKey(String vaultId) async {
    await _storage.delete(key: _storageKey(vaultId));
  }
}
