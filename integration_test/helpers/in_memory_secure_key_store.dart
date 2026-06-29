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
}
