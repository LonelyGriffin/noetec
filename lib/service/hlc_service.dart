// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

class HlcService {
  HlcService(this._vaultSystem, this._deviceService) {
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final VaultSystem _vaultSystem;
  final IDeviceService _deviceService;

  String? _deviceId;
  String? _vaultRootPath;
  Hlc? _lastHlc;

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      final device = _deviceService.currentDevice;
      if (device == null) return;
      _deviceId = device.truncatedDeviceId;
      _vaultRootPath = vault.rootPath;
      final storedKey = device.lastHlc;
      if (storedKey != null) {
        try {
          _lastHlc = Hlc.fromKey(storedKey);
        } catch (_) {
          _lastHlc = null;
        }
      } else {
        _lastHlc = null;
      }
    } else {
      _deviceId = null;
      _vaultRootPath = null;
      _lastHlc = null;
    }
  }

  Hlc now() {
    assert(_deviceId != null, 'HlcService not activated (no vault open)');
    final deviceId = _deviceId!;
    final hlc = Hlc.now(_lastHlc, deviceId);
    _lastHlc = hlc;
    _storeHlc(hlc.toKey());
    return hlc;
  }

  Hlc receive(Hlc remote) {
    assert(_deviceId != null, 'HlcService not activated (no vault open)');
    final deviceId = _deviceId!;
    final hlc = Hlc.receive(remote, _lastHlc, deviceId);
    _lastHlc = hlc;
    _storeHlc(hlc.toKey());
    return hlc;
  }

  Hlc? get lastHlc => _lastHlc;

  Future<void> _storeHlc(String key) async {
    final vaultRootPath = _vaultRootPath;
    if (vaultRootPath == null) return;
    await _deviceService.updateLastHlc(vaultRootPath, key);
  }

  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
  }
}
