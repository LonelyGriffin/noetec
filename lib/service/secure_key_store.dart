// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ISecureKeyStore {
  Future<void> storeDevicePrivateKey(String vaultId, String devicePrivateKeyBase64);
  Future<String?> readDevicePrivateKey(String vaultId);
  Future<bool> hasDevicePrivateKey(String vaultId);
  Future<void> deleteDevicePrivateKey(String vaultId);

  /// Stores the 32-byte identity entropy seed (base64url) for [vaultId].
  ///
  /// ADR-0007 §2: the seed lives ONLY in flutter_secure_storage and is never
  /// written to the vault.
  Future<void> storeIdentitySeed(String vaultId, String seedBase64Url);
  Future<String?> readIdentitySeed(String vaultId);
  Future<bool> hasIdentitySeed(String vaultId);

  /// Stores the 32-byte Ed25519 identity secret seed (base64url) for [vaultId].
  Future<void> storeIdentityPrivateKey(String vaultId, String identityPrivateKeyBase64Url);
  Future<String?> readIdentityPrivateKey(String vaultId);
}

class SecureKeyStoreImpl implements ISecureKeyStore {
  SecureKeyStoreImpl({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _storageKey(String vaultId) {
    return 'noetec.device_private_key.$vaultId';
  }

  @override
  Future<void> storeDevicePrivateKey(String vaultId, String devicePrivateKeyBase64) async {
    await _storage.write(key: _storageKey(vaultId), value: devicePrivateKeyBase64);
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

  @override
  Future<void> storeIdentitySeed(String vaultId, String seedBase64Url) async {
    await _storage.write(key: 'noetec.identity_seed.$vaultId', value: seedBase64Url);
  }

  @override
  Future<String?> readIdentitySeed(String vaultId) async {
    return _storage.read(key: 'noetec.identity_seed.$vaultId');
  }

  @override
  Future<bool> hasIdentitySeed(String vaultId) async {
    final value = await _storage.read(key: 'noetec.identity_seed.$vaultId');
    return value != null;
  }

  @override
  Future<void> storeIdentityPrivateKey(String vaultId, String identityPrivateKeyBase64Url) async {
    await _storage.write(key: 'noetec.identity_private_key.$vaultId', value: identityPrivateKeyBase64Url);
  }

  @override
  Future<String?> readIdentityPrivateKey(String vaultId) async {
    return _storage.read(key: 'noetec.identity_private_key.$vaultId');
  }
}
