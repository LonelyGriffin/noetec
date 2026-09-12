// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:bip39/bip39.dart' as bip39;
import 'package:command_it/command_it.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/user/user_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/service/user_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

/// A user-facing error surfaced by a [UserDeviceController] command.
///
/// The original exception is wrapped (and kept only in memory for debugging)
/// so the UI can show a short, non-sensitive message: internal state, paths,
/// and registry internals must never reach the screen (NOET-33 acceptance
/// criterion "no private material is written to UI state or logs").
final class UserDeviceError implements Exception {
  UserDeviceError(this.message, [Object? cause]) : _cause = cause;

  /// The short, user-presentable message (e.g. "Invalid public key").
  final String message;

  /// The underlying exception, kept in memory only (never shown to the user).
  // ignore: unused_field
  final Object? _cause;

  @override
  String toString() => message;
}

/// A point-in-time, read-only view of the user & device state for the active
/// vault. It is the single source of truth the settings UI renders from; the
/// [UserDeviceController.refreshCommand] repopulates it.
///
/// Only **public** material is held here (names, ids, public keys, registry
/// records). The identity seed and any private key are never stored in this
/// snapshot — they are read from secure storage on demand and returned to the
/// caller for one-time display (ADR-0007 §2).
final class UserDeviceSnapshot {
  const UserDeviceSnapshot({required this.operator, required this.device, required this.users, required this.devices});

  /// The local (operator) identity, or `null` when the vault has none.
  final UserIdentity? operator;

  /// The local device, or `null` when none could be resolved.
  final DeviceIdentity? device;

  /// The reconciled `users.json` registry, or `null` when absent.
  final UserRegistry? users;

  /// The reconciled `devices/<operatorId>.json` registry for the operator,
  /// or `null` when absent (or there is no operator identity).
  final DeviceRegistry? devices;
}

/// Owns the reactive user & device state and exposes the user-facing
/// management operations as [Command]s (the `it` ecosystem).
///
/// This is the view-model behind the settings user/device panel (NOET-33).
/// Widgets call the commands and render the [state] notifier; there is no
/// `setState` anywhere.
///
/// Backed by the building blocks produced by NOET-26/29/32:
/// - [IUserService] (identity + seed),
/// - [IRegistryService] (registry files),
/// - [IDeviceService] (local device),
/// - [IOnboardingService] (the signed user/device operations).
///
/// All flows operate on the currently open vault ([VaultSystem.currentVault])
/// and surface [UserDeviceError] when no vault is open.
final class UserDeviceController {
  UserDeviceController({
    required VaultSystem vaultSystem,
    required IUserService userService,
    required IDeviceService deviceService,
    required IRegistryService registry,
    required IOnboardingService onboarding,
    required ISecureKeyStore secureKeyStore,
  }) : _vaultSystem = vaultSystem,
       _userService = userService,
       _deviceService = deviceService,
       _registry = registry,
       _onboarding = onboarding,
       _secureKeyStore = secureKeyStore {
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final VaultSystem _vaultSystem;
  final IUserService _userService;
  final IDeviceService _deviceService;
  final IRegistryService _registry;
  final IOnboardingService _onboarding;
  final ISecureKeyStore _secureKeyStore;

  /// The reactive user & device state. `null` until the first successful
  /// [refreshCommand] (or when no vault is open).
  final state = CustomValueNotifier<UserDeviceSnapshot?>(null);

  /// Reloads the operator identity, the local device, `users.json`, and the
  /// operator's device registry into [state].
  late final refreshCommand = Command.createAsyncNoParamNoResult(_refresh, debugName: 'userDeviceRefresh');

  /// Adds a member to `users.json` from a foreign public key (owner only).
  late final addUserCommand = Command.createAsyncNoResult<({String name, String publicKeyBase64Url})>(_addUser, debugName: 'userDeviceAddUser');

  /// Tombstones a user in `users.json` (owner only, not the owner).
  late final revokeUserCommand = Command.createAsyncNoResult<String>(_revokeUser, debugName: 'userDeviceRevokeUser');

  /// Tombstones a device in the operator's `devices/<operatorId>.json`.
  late final revokeDeviceCommand = Command.createAsyncNoResult<String>(_revokeDevice, debugName: 'userDeviceRevokeDevice');

  /// Renames the local device (persisted to `.noetec/device.json`).
  late final renameDeviceCommand = Command.createAsyncNoResult<String>(_renameDevice, debugName: 'userDeviceRenameDevice');

  /// The currently open vault; user/device management requires one.
  VaultEntity get _activeVault {
    final vault = _vaultSystem.currentVault.value;
    if (vault == null) {
      throw StateError('no vault is open');
    }
    return vault;
  }

  /// Whether the local operator is the owner of `users.json` (only the owner
  /// can add/revoke users).
  bool get isOperatorOwner {
    final snapshot = state.value;
    final operator = snapshot?.operator;
    final users = snapshot?.users;
    return operator != null && users != null && users.ownerUserId == operator.userId;
  }

  void _onVaultChanged() {
    // The state is tied to the open vault; a new (or no) vault invalidates it.
    state.value = null;
  }

  // --- Load ----------------------------------------------------------------

  Future<void> _refresh() async {
    final vault = _vaultSystem.currentVault.value;
    if (vault == null) {
      // No vault open: a legitimate empty state, not an error.
      state.value = null;
      return;
    }

    // The operator identity (from `.noetec/identity.json`).
    final operator = await _userService.loadIdentity(vault.rootPath);

    // The local device. `ensureDevice` is idempotent (vault open already
    // guarantees one); calling it keeps the in-memory device fresh.
    final device = await _deviceService.ensureDevice(vault.rootPath, vault.id);

    // The user registry (`users.json`), if present and valid.
    final users = await _safeLoad(() => _registry.loadUserRegistry());

    // The operator's device registry, if the operator exists.
    DeviceRegistry? devices;
    if (operator != null) {
      devices = await _safeLoad(() => _registry.loadDeviceRegistry(operator.userId));
    }

    state.value = UserDeviceSnapshot(operator: operator, device: device, users: users, devices: devices);
  }

  Future<T?> _safeLoad<T>(Future<T?> Function() loader) async {
    try {
      return await loader();
    } on Exception {
      // A corrupt/absent registry is a legitimate state (shown as "no
      // registry"); a load failure must not take the whole panel down.
      return null;
    }
  }

  // --- Seed (on demand, never stored in [state]) ---------------------------

  /// Reconstructs the 24-word BIP39 backup of the identity seed from secure
  /// storage and returns it for one-time display (NOET-26, ADR-0007 §2).
  ///
  /// Returns `null` when the vault has no identity or the seed is not in
  /// secure storage. The mnemonic is not persisted anywhere and not held in
  /// reactive state — the caller shows it immediately and drops it.
  Future<String?> showSeed() async {
    final vault = _activeVault;
    final operator = await _userService.loadIdentity(vault.rootPath);
    if (operator == null) return null;

    final seedBase64Url = await _secureKeyStore.readIdentitySeed(vault.id);
    if (seedBase64Url == null) return null;

    final seed = base64UrlDecode(seedBase64Url);
    final hex = seed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return bip39.entropyToMnemonic(hex);
  }

  // --- Operations ----------------------------------------------------------

  Future<void> _addUser(({String name, String publicKeyBase64Url}) params) async {
    try {
      await _onboarding.addUserFromPublicKey(name: params.name, publicKeyBase64Url: params.publicKeyBase64Url);
      await _refresh();
    } catch (e) {
      throw _mapError(e, argumentMessage: 'Invalid public key: it must be a 32-byte base64url Ed25519 identity key.');
    }
  }

  Future<void> _revokeUser(String userId) async {
    try {
      await _onboarding.revokeUserOnboarding(userId);
      await _refresh();
    } catch (e) {
      throw _mapError(e, argumentMessage: 'Cannot revoke this user.');
    }
  }

  Future<void> _revokeDevice(String deviceUuid) async {
    try {
      await _onboarding.revokeDeviceOnboarding(deviceUuid);
      await _refresh();
    } catch (e) {
      throw _mapError(e, argumentMessage: 'Cannot revoke this device.');
    }
  }

  Future<void> _renameDevice(String newName) async {
    final name = newName.trim();
    if (name.isEmpty) {
      throw UserDeviceError('Device name must not be empty.');
    }
    try {
      await _deviceService.renameDevice(_activeVault.rootPath, name);
      await _refresh();
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// Translates a raw error from the services into a short, non-sensitive
  /// [UserDeviceError] for the UI. The domain services throw [ArgumentError]
  /// (bad input, e.g. an invalid public key) and [StateError] (no vault,
  /// wrong authority, owner protections); neither is safe to surface verbatim
  /// (they may embed ids/paths), so they are remapped here (NOET-33).
  UserDeviceError _mapError(Object error, {String? argumentMessage}) {
    if (error is UserDeviceError) return error;
    if (error is ArgumentError) return UserDeviceError(argumentMessage ?? 'Invalid input.', error);
    if (error is StateError) return UserDeviceError(_stateErrorMessage(error), error);
    return UserDeviceError('Something went wrong. Please try again.', error);
  }

  /// Maps a [StateError] to a short user-facing message (never exposing the
  /// raw message, which may contain ids/paths).
  String _stateErrorMessage(StateError e) {
    final raw = e.message.toString();
    if (raw.contains('no vault is open') || raw.contains('open vault')) {
      return 'No vault is open.';
    }
    if (raw.contains('not the authority') || raw.contains('administers users.json') || raw.contains('only the owner')) {
      return 'Only the owner can do that.';
    }
    if (raw.contains('cannot revoke the owner')) {
      return 'The owner cannot be revoked.';
    }
    if (raw.contains('no local identity')) {
      return 'No identity for this vault yet.';
    }
    return 'Something went wrong. Please try again.';
  }

  /// Releases the listeners and notifiers.
  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    refreshCommand.dispose();
    addUserCommand.dispose();
    revokeUserCommand.dispose();
    revokeDeviceCommand.dispose();
    renameDeviceCommand.dispose();
    state.dispose();
  }
}
