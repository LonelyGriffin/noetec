import 'package:noetec/service/secure_key_store.dart';

class InMemorySecureKeyStore implements ISecureKeyStore {
  final _store = <String, String>{};

  @override
  Future<void> storeDevicePrivateKey(
    String vaultId,
    String devicePrivateKeyBase64,
  ) async {
    _store[vaultId] = devicePrivateKeyBase64;
  }

  @override
  Future<String?> readDevicePrivateKey(String vaultId) async {
    return _store[vaultId];
  }

  @override
  Future<bool> hasDevicePrivateKey(String vaultId) async {
    return _store.containsKey(vaultId);
  }

  @override
  Future<void> deleteDevicePrivateKey(String vaultId) async {
    _store.remove(vaultId);
  }

  @override
  Future<void> storeIdentitySeed(String vaultId, String seedBase64Url) async {
    _store['identity_seed.$vaultId'] = seedBase64Url;
  }

  @override
  Future<String?> readIdentitySeed(String vaultId) async {
    return _store['identity_seed.$vaultId'];
  }

  @override
  Future<bool> hasIdentitySeed(String vaultId) async {
    return _store.containsKey('identity_seed.$vaultId');
  }

  @override
  Future<void> storeIdentityPrivateKey(
    String vaultId,
    String identityPrivateKeyBase64Url,
  ) async {
    _store['identity_private.$vaultId'] = identityPrivateKeyBase64Url;
  }

  @override
  Future<String?> readIdentityPrivateKey(String vaultId) async {
    return _store['identity_private.$vaultId'];
  }
}
