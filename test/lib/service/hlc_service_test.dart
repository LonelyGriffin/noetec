import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../helpers/test_fakes.dart';

void main() {
  group('HlcService —', () {
    late VaultSystem vaultSystem;
    late FakeDeviceService deviceService;
    late HlcService service;

    setUp(() {
      vaultSystem = createTestVaultSystem(deviceService: FakeDeviceService());
      deviceService = vaultSystem.currentVault.value == null
          ? FakeDeviceService()
          : FakeDeviceService();
      vaultSystem = createTestVaultSystem(deviceService: deviceService);
      service = HlcService(vaultSystem, deviceService);
    });

    tearDown(() {
      service.dispose();
      vaultSystem.dispose();
    });

    void activateVault() {
      deviceService.setDevice(
        DeviceIdentity(
          uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          name: 'Test',
          createdAt: DateTime(2026),
          lastHlc: null,
          publicKey: null,
        ),
      );
      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );
    }

    test('now() generates HLC after activation', () {
      activateVault();
      final hlc = service.now();
      expect(hlc, isNotNull);
      expect(hlc.deviceId, 'aaaaaaaa');
    });

    test('restores lastHlc from device stored key', () {
      deviceService.setDevice(
        DeviceIdentity(
          uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          name: 'Test',
          createdAt: DateTime(2026),
          lastHlc: '1705312200000-0001-aabbccdd',
          publicKey: null,
        ),
      );
      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );

      expect(service.lastHlc, isNotNull);
      expect(service.lastHlc!.toKey(), '1705312200000-0001-aabbccdd');
    });

    test('ignores corrupt stored key', () {
      deviceService.setDevice(
        DeviceIdentity(
          uuid: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          name: 'Test',
          createdAt: DateTime(2026),
          lastHlc: 'corrupt-key',
          publicKey: null,
        ),
      );
      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );

      expect(service.lastHlc, isNull);
    });

    test('resets state on vault close', () {
      activateVault();
      service.now();
      expect(service.lastHlc, isNotNull);

      vaultSystem.currentVault.value = null;
      expect(service.lastHlc, isNull);
    });
  });
}
