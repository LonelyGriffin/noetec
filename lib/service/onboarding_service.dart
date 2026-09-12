// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:logging/logging.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/user/user_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/user_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

/// The outcome of [IOnboardingService.createVaultOnboarding] (and
/// [IOnboardingService.bootstrapOwnerIdentity]): the created owner identity,
/// the 24-word BIP39 backup of the identity seed (shown once, ADR-0007 §2),
/// the local device, and the two registry files the flow wrote.
final class CreateVaultResult {
  const CreateVaultResult({required this.owner, required this.mnemonic, required this.userRegistry, required this.deviceRegistry, required this.device});

  /// The created owner identity.
  final UserIdentity owner;

  /// The 24-word BIP39 mnemonic backing up the 32-byte identity seed. It is
  /// the only copy that ever leaves secure storage: the UI shows it once for
  /// backup and never stores it again (ADR-0007 §2).
  final String mnemonic;

  /// The `users.json` registry after the owner record was written
  /// (self-signed: `addedBy` = the new owner, §3.2).
  final UserRegistry userRegistry;

  /// The `devices/<ownerId>.json` registry after the first device
  /// certificate was written (§3.3).
  final DeviceRegistry deviceRegistry;

  /// The local (first) device bound to the owner.
  final DeviceIdentity device;
}

/// The outcome of [IOnboardingService.restoreFromSeed]: the restored identity
/// (deterministic in its public key) and the device registry after the local
/// device was bound.
final class RestoreResult {
  const RestoreResult({required this.identity, required this.deviceRegistry, required this.device});

  /// The restored identity. Its `userId` matches the existing `users.json`
  /// record when one was found by public key; otherwise it is a fresh UUID
  /// (the user is not yet registered and must be added by the owner).
  final UserIdentity identity;

  /// The `devices/<userId>.json` registry after the binding (the new device
  /// certificate is signed by the user's identity key, §3.3).
  final DeviceRegistry deviceRegistry;

  /// The local device that was bound.
  final DeviceIdentity device;
}

/// The outcome of [IOnboardingService.addUserFromPublicKey].
final class AddUserResult {
  const AddUserResult({required this.userRegistry, required this.user});

  /// The `users.json` registry after the new record was appended and the
  /// whole file re-signed by the owner (§3.6).
  final UserRegistry userRegistry;

  /// The added user's record.
  final UserRecord user;
}

/// Orchestrates the user/device onboarding flows on top of the building
/// blocks: [IUserService] (identity + seed, NOET-26), [IRegistryService]
/// (registry files, NOET-29), [IDeviceService] (local device), and the
/// key/secret stores they use (NOET-32).
///
/// All flows are offline (no server) and operate on the currently open vault
/// ([VaultSystem.currentVault]); they throw [StateError] when no vault is
/// open.
///
/// Flows (sync-security.md §3.6, ADR-0007):
/// - [createVaultOnboarding] — vault creation: generate the owner identity +
///   the first device, write `users.json` (owner record, self-signed) and
///   `devices/<ownerId>.json` (first device certificate), and return the
///   24-word seed for one-time backup.
/// - [bootstrapOwnerIdentity] — an existing vault opened without an identity:
///   the first opened user becomes the owner (same files as above).
/// - [restoreFromSeed] — enter a 24-word seed, derive the identity key, and
///   bind the local device (new device key + signed certificate appended to
///   `devices/<userId>.json`). The identity **key** is deterministic; the
///   `userId` is resolved from the user's `users.json` record by public key.
/// - [addUserFromPublicKey] — the owner adds a user from a foreign public
///   key only (the new user generates their own seed locally; it never
///   leaves their device) and signs the `users.json` record.
/// - [revokeDeviceOnboarding] — the owner of a device tombstones its record
///   in their own `devices/<userId>.json`.
/// - [revokeUserOnboarding] — the owner tombstones a user record in
///   `users.json`.
abstract interface class IOnboardingService {
  /// Creates the owner identity + first device and writes both registry files
  /// for a freshly created vault. Throws [StateError] when the vault already
  /// has an identity (use [restoreFromSeed] or [addUserFromPublicKey]).
  Future<CreateVaultResult> createVaultOnboarding({required String ownerName, String? deviceName});

  /// Bootstraps an existing vault that was opened without an identity: the
  /// first opened user becomes the owner. Throws [StateError] when the vault
  /// already has an identity or an established `users.json`.
  Future<CreateVaultResult> bootstrapOwnerIdentity({required String ownerName, String? deviceName});

  /// Restores the identity from a 24-word BIP39 [mnemonic] and binds the
  /// local device to it (regenerating the binding for an existing device is
  /// safe: `addDevice` keeps the original `issuedAt`).
  Future<RestoreResult> restoreFromSeed({required String mnemonic, String? deviceName});

  /// Adds [name] to `users.json` under a fresh UUID, using only the foreign
  /// [publicKeyBase64Url] (base64url Ed25519 identity key, §2.1). The owner
  /// signs the record and re-signs the file.
  Future<AddUserResult> addUserFromPublicKey({required String name, required String publicKeyBase64Url});

  /// Revokes [deviceUuid] in the operator's own `devices/<operatorId>.json`
  /// (tombstone, §3.6). The registry enforces that the operator owns the
  /// device.
  Future<DeviceRegistry> revokeDeviceOnboarding(String deviceUuid);

  /// Revokes [userId] in `users.json` (tombstone, §3.6). The registry
  /// enforces that the operator is the owner and that the target is not the
  /// owner.
  Future<UserRegistry> revokeUserOnboarding(String userId);
}

class OnboardingServiceImpl implements IOnboardingService {
  OnboardingServiceImpl({
    required IFileSystemService fileSystem,
    required IDeviceService deviceService,
    required IUserService userService,
    required IRegistryService registry,
    required ICryptoService crypto,
    required IIdService idService,
    required VaultSystem vaultSystem,
  }) : _fileSystem = fileSystem,
       _deviceService = deviceService,
       _userService = userService,
       _registry = registry,
       _crypto = crypto,
       _idService = idService,
       _vaultSystem = vaultSystem,
       _log = Logger('OnboardingService');

  final IFileSystemService _fileSystem;
  final IDeviceService _deviceService;
  final IUserService _userService;
  final IRegistryService _registry;
  final ICryptoService _crypto;
  final IIdService _idService;
  final VaultSystem _vaultSystem;
  final Logger _log;

  /// The currently open vault; onboarding operates only on the active vault.
  VaultEntity get _activeVault {
    final vault = _vaultSystem.currentVault.value;
    if (vault == null) {
      throw StateError('onboarding requires an open vault');
    }
    return vault;
  }

  // --- Flow 1: create vault / bootstrap ------------------------------------

  @override
  Future<CreateVaultResult> createVaultOnboarding({required String ownerName, String? deviceName}) async {
    final vault = _activeVault;
    final existing = await _userService.loadIdentity(vault.rootPath);
    if (existing != null) {
      throw StateError('vault already has identity ${existing.userId}; createVaultOnboarding is only for new vaults (use restoreFromSeed or addUserFromPublicKey instead)');
    }
    return _onboardOwner(vault: vault, ownerName: ownerName, deviceName: deviceName);
  }

  @override
  Future<CreateVaultResult> bootstrapOwnerIdentity({required String ownerName, String? deviceName}) async {
    final vault = _activeVault;
    final existing = await _userService.loadIdentity(vault.rootPath);
    if (existing != null) {
      throw StateError('vault already has identity ${existing.userId}; bootstrap is only for vaults without an identity');
    }
    final users = await _registry.loadUserRegistry();
    if (users != null) {
      throw StateError('users.json already exists (owner ${users.ownerUserId}); the vault already has an established owner');
    }
    return _onboardOwner(vault: vault, ownerName: ownerName, deviceName: deviceName);
  }

  /// Creates the owner identity and first device and writes the two registry
  /// files (shared by vault creation and bootstrap).
  Future<CreateVaultResult> _onboardOwner({required VaultEntity vault, required String ownerName, String? deviceName}) async {
    final root = vault.rootPath;

    // The first device. `ensureDevice` is idempotent (vault creation/open
    // already guarantees one) — calling it here satisfies the "generate the
    // first device" contract even for a caller that skips it.
    final device = await _deviceService.ensureDevice(root, vault.id);

    // The 24-word mnemonic is the one-time backup of the identity seed
    // (ADR-0007 §2); it is returned for display, never persisted anywhere
    // but secure storage (and even there only the 32-byte seed, not the
    // mnemonic).
    final created = await _userService.createIdentity(root, vault.id, name: ownerName, role: 'owner');

    await _ensureSyncDirectories(root);

    // Owner record in users.json (self-signed: addedBy = the new owner, §3.2).
    final userRegistry = await _registry.addUser(userId: created.identity.userId, name: created.identity.name, publicKey: created.identity.publicKey, role: 'owner');

    // First device certificate in devices/<ownerId>.json (§3.3).
    final deviceRegistry = await _registry.addDevice(deviceUuid: device.uuid, devicePublicKey: _devicePublicKey(device), deviceName: deviceName ?? device.name);

    _log.info('Onboarded owner ${created.identity.userId} with device ${device.uuid}');
    return CreateVaultResult(owner: created.identity, mnemonic: created.mnemonic, userRegistry: userRegistry, deviceRegistry: deviceRegistry, device: device);
  }

  // --- Flow 2: restore identity from seed ----------------------------------

  @override
  Future<RestoreResult> restoreFromSeed({required String mnemonic, String? deviceName}) async {
    final vault = _activeVault;
    final root = vault.rootPath;

    // Validate the mnemonic first, before touching any state.
    final entropy = _entropyFromMnemonic(mnemonic);

    final device = await _deviceService.ensureDevice(root, vault.id);

    // The users.json registry is the authoritative source of the restored
    // user's id (IUserService.restoreIdentity): a record whose public key
    // matches the derived key keeps its userId, so the restored identity
    // lines up with the registry record that the owner signed.
    final derived = await _crypto.deriveIdentityKeyPair(entropy);
    String? resolvedUserId;
    final existingUsers = await _registry.loadUserRegistry();
    if (existingUsers != null) {
      for (final record in existingUsers.users) {
        if (record.publicKey == derived.publicKeyBase64Url) {
          resolvedUserId = record.userId;
          break;
        }
      }
      if (resolvedUserId == null) {
        throw StateError('this seed does not belong to the vault: no users.json record has the derived public key — the vault is owned by ${existingUsers.ownerUserId}');
      }
    }

    final identity = await _userService.restoreIdentity(root, vault.id, mnemonic, userId: resolvedUserId);

    // Bind the local device: the user signs a fresh certificate for this
    // device (addDevice keeps issuedAt when re-binding an existing one).
    await _ensureSyncDirectories(root);
    final deviceRegistry = await _registry.addDevice(deviceUuid: device.uuid, devicePublicKey: _devicePublicKey(device), deviceName: deviceName ?? device.name);

    _log.info('Restored identity ${identity.userId} and bound device ${device.uuid}');
    return RestoreResult(identity: identity, deviceRegistry: deviceRegistry, device: device);
  }

  // --- Flow 3: add user from a foreign public key --------------------------

  @override
  Future<AddUserResult> addUserFromPublicKey({required String name, required String publicKeyBase64Url}) async {
    final vault = _activeVault;

    // Only the foreign public key arrives: the new user generated their own
    // seed locally and it never leaves their device (flow 3). Validate it as
    // a base64url 32-byte Ed25519 key (§2.1) before it is pinned in
    // users.json.
    final normalized = _normalizeIdentityKey(publicKeyBase64Url);
    await _ensureSyncDirectories(vault.rootPath);

    final userId = _idService.generateId();
    final userRegistry = await _registry.addUser(userId: userId, name: name, publicKey: normalized, role: 'member');
    final user = userRegistry.usersById[userId];
    if (user == null) {
      throw StateError('users.json does not contain the record just written for $userId');
    }
    _log.info('Added user $userId ($name) to users.json');
    return AddUserResult(userRegistry: userRegistry, user: user);
  }

  // --- Flows 4 & 5: revocation ---------------------------------------------

  @override
  Future<DeviceRegistry> revokeDeviceOnboarding(String deviceUuid) async {
    // The operator must own the device (devices/<operatorId>.json); the
    // registry enforces it and throws otherwise.
    final registry = await _registry.revokeDevice(deviceUuid);
    _log.info('Revoked device $deviceUuid from ${registry.userId}');
    return registry;
  }

  @override
  Future<UserRegistry> revokeUserOnboarding(String userId) async {
    // The operator must be the owner, and the owner cannot revoke themself;
    // the registry enforces both.
    final registry = await _registry.revokeUser(userId);
    _log.info('Revoked user $userId from users.json');
    return registry;
  }

  // --- Helpers --------------------------------------------------------------

  /// Ensures `.sync/` and `.sync/devices/` exist. Vault creation only creates
  /// `.sync/pages/`, and the registry's atomic writes do not create parent
  /// directories — so the onboarding flows create them explicitly.
  Future<void> _ensureSyncDirectories(String root) async {
    final sync = '$root/.sync';
    if (!await _fileSystem.directoryExists(sync)) {
      await _fileSystem.createDirectory(sync);
    }
    final devices = '$sync/devices';
    if (!await _fileSystem.directoryExists(devices)) {
      await _fileSystem.createDirectory(devices);
    }
  }

  /// The device's public key normalized to base64url without padding
  /// (sync-security.md §2.1 "Encoding migration": legacy `device.json` values
  /// are padded standard base64).
  String _devicePublicKey(DeviceIdentity device) {
    final key = device.publicKey;
    if (key == null) {
      throw StateError('device ${device.uuid} has no public key; it cannot be bound by certificate');
    }
    return normalizeToBase64Url(key);
  }

  /// Normalizes a foreign Ed25519 identity key to base64url without padding
  /// (§2.1). Throws [ArgumentError] when the input is not a 32-byte key.
  String _normalizeIdentityKey(String publicKeyBase64Url) {
    final List<int> bytes;
    try {
      bytes = base64UrlDecode(publicKeyBase64Url);
    } on FormatException {
      throw ArgumentError.value(publicKeyBase64Url, 'publicKeyBase64Url', 'not a valid base64url key');
    }
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'publicKeyBase64Url', 'an Ed25519 public key must be 32 bytes');
    }
    return base64UrlEncodeNoPad(bytes);
  }

  /// The 32-byte entropy seed behind a BIP39 [mnemonic] (ADR-0007 §1: the
  /// mnemonic is only a human-readable backup of the seed).
  Uint8List _entropyFromMnemonic(String mnemonic) {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw ArgumentError.value(mnemonic, 'mnemonic', 'Invalid BIP39 mnemonic');
    }
    final hex = bip39.mnemonicToEntropy(mnemonic);
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
