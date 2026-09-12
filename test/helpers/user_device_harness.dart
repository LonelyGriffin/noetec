// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/service/user_device_controller.dart';
import 'package:noetec/service/user_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_signing.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import 'test_fakes.dart';

/// A [FakeFileSystemService] with a working rename (the registry service's
/// atomic write relies on `.tmp` → canonical renames).
class UserDeviceTestFs extends FakeFileSystemService {
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final content = files.remove(oldPath);
    if (content != null) files[newPath] = content;
    if (dirs.remove(oldPath)) dirs.add(newPath);
  }
}

/// One in-memory "device" running the real identity/registry/onboarding stack
/// against an in-memory vault, plus a [UserDeviceController] under test.
///
/// The same real services the app wires (via get_it) are used, so the
/// controller is exercised end-to-end (signing, reconciliation, secure
/// storage) with no filesystem.
final class UserDeviceHarness {
  UserDeviceHarness._({
    required this.fs,
    required this.keyStore,
    required this.deviceService,
    required this.userService,
    required this.registry,
    required this.vault,
    required this.onboarding,
    required this.controller,
    required this.signing,
  });

  final UserDeviceTestFs fs;
  final FakeSecureKeyStore keyStore;
  final DeviceServiceImpl deviceService;
  final UserServiceImpl userService;
  final RegistryServiceImpl registry;
  final VaultSystem vault;
  final OnboardingServiceImpl onboarding;
  final UserDeviceController controller;
  final RegistrySigning signing;

  static const String root = '/vault';
  static const String vaultId = 'v1';
}

/// Every harness created this run, disposed exactly once in the test's
/// tearDown (the controller and the vault both subscribe to the vault
/// notifier and must be released).
final _harnessesToDispose = <UserDeviceHarness>[];

void disposeUserDeviceHarnesses() {
  for (final h in _harnessesToDispose) {
    h.controller.dispose();
    h.vault.dispose();
  }
  _harnessesToDispose.clear();
}

/// Builds a fresh in-memory stack with the vault **open** but no identity
/// (the caller runs onboarding).
Future<UserDeviceHarness> buildUserDeviceHarness() async {
  final fs = UserDeviceTestFs();
  final keyStore = FakeSecureKeyStore();
  // Real `IdService` (uuid v4): the device UUID must be a 32-hex value because
  // `DeviceIdentity.truncatedDeviceId` is `uuid.replaceAll('-','').substring(0,8)`
  // (an HLC node id) — the shared `FakeIdService`'s `test-id-N` ids are too short.
  final idService = IdService();
  final crypto = CryptoServiceImpl();
  final signing = RegistrySigning(crypto);

  final deviceService = DeviceServiceImpl(fs, idService, crypto, keyStore);
  final userService = UserServiceImpl(fs, idService, crypto, keyStore);
  final vault = VaultSystem(fs, FakeVaultRepository(), idService, deviceService);
  final hlc = HlcService(vault, deviceService);
  final registry = RegistryServiceImpl(fileSystem: fs, hlcService: hlc, crypto: crypto, secureKeyStore: keyStore, vaultSystem: vault);
  final onboarding = OnboardingServiceImpl(
    fileSystem: fs,
    deviceService: deviceService,
    userService: userService,
    registry: registry,
    crypto: crypto,
    idService: idService,
    vaultSystem: vault,
  );
  final controller = UserDeviceController(
    vaultSystem: vault,
    userService: userService,
    deviceService: deviceService,
    registry: registry,
    onboarding: onboarding,
    secureKeyStore: keyStore,
  );

  // "Open" the vault the way VaultSystem does: the device is guaranteed
  // before currentVault is set (HlcService's listener needs it).
  await deviceService.ensureDevice(UserDeviceHarness.root, UserDeviceHarness.vaultId);
  vault.currentVault.value = VaultEntity(id: UserDeviceHarness.vaultId, name: 'Vault', rootPath: UserDeviceHarness.root, createdAt: DateTime(2026));

  final harness = UserDeviceHarness._(
    fs: fs,
    keyStore: keyStore,
    deviceService: deviceService,
    userService: userService,
    registry: registry,
    vault: vault,
    onboarding: onboarding,
    controller: controller,
    signing: signing,
  );
  _harnessesToDispose.add(harness);
  return harness;
}

/// Convenience: open an on-boarded owner vault (owner identity + first device
/// + `users.json` + `devices/<ownerId>.json`).
Future<(UserDeviceHarness, CreateVaultResult)> buildOnboardedHarness() async {
  final h = await buildUserDeviceHarness();
  final result = await h.onboarding.createVaultOnboarding(ownerName: 'Owner', deviceName: 'First Laptop');
  return (h, result);
}

/// A 32-byte base64url Ed25519 public key (valid, for "add user" inputs).
String validPublicKey(int seed) {
  final bytes = List<int>.generate(32, (i) => (seed + i * 7) & 0xff);
  return base64UrlEncodeNoPad(bytes);
}
