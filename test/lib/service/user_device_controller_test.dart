// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:bip39/bip39.dart' as bip39;
import 'package:command_it/command_it.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/user_device_controller.dart';

import '../../helpers/user_device_harness.dart';

/// Runs [start] and swallows any error the command rethrows. The failure is
/// observed via the command's [Command.errors] notifier (asserted by the
/// caller), not the thrown exception.
///
/// [`Command.runAsync`] rethrows on an error (it completes its future with
/// the error after routing it through the error filter), so a bare `await`
/// would fail the test. The side effects (state, error) are what we assert on.
Future<void> runSwallow(Future<void> Function() start) async {
  try {
    await start();
  } catch (_) {
    // Expected for the error paths under test; the command surfaces the error
    // on its `errors` notifier, which the assertion below the call checks.
  }
}

/// Waits until [command] has recorded an error on its [Command.errors]
/// notifier. The notifier is populated by a deferred `listen_it` listener, so
/// it may not be set the instant `runAsync` rethrows; poll for it.
Future<void> settleErrors(Command command) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (command.errors.value == null && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  setUp(() {
    // The default error filter routes errors to the global handler when there
    // is no local listener. Register a no-op so erroring commands don't
    // surface an unhandled "no global handler" assertion in tests.
    Command.globalExceptionHandler = (_, _) {};
  });

  tearDown(disposeUserDeviceHarnesses);

  group('refreshCommand —', () {
    test('loads operator, device, users and devices from an onboarded vault', () async {
      final (h, result) = await buildOnboardedHarness();

      await h.controller.refreshCommand.runAsync();

      final snapshot = h.controller.state.value;
      expect(snapshot, isNotNull);
      expect(snapshot!.operator?.userId, result.owner.userId);
      expect(snapshot.operator?.name, 'Owner');
      expect(snapshot.device?.uuid, result.device.uuid);
      expect(snapshot.users?.ownerUserId, result.owner.userId);
      expect(snapshot.users?.users, hasLength(1));
      expect(snapshot.devices?.devices, hasLength(1));
      expect(snapshot.devices?.devices.single.deviceUuid, result.device.uuid);
    });

    test('is a no-op (state stays null) when no vault is open', () async {
      final h = await buildUserDeviceHarness();
      h.vault.currentVault.value = null; // close the vault

      await h.controller.refreshCommand.runAsync();

      expect(h.controller.state.value, isNull);
      expect(h.controller.refreshCommand.errors.value, isNull);
    });
  });

  group('isOperatorOwner —', () {
    test('is true for the owner of users.json', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();
      expect(h.controller.isOperatorOwner, isTrue);
    });
  });

  group('addUserCommand —', () {
    test('adds a member from a valid public key', () async {
      final (h, result) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await h.controller.addUserCommand.runAsync((name: 'Alice', publicKeyBase64Url: validPublicKey(1)));

      final users = h.controller.state.value!.users!;
      expect(users.users, hasLength(2));
      final alice = users.users.firstWhere((u) => u.name == 'Alice');
      expect(alice.role, 'member');
      expect(alice.isRemoved, isFalse);
      expect(alice.addedBy, result.owner.userId);
    });

    test('rejects an invalid public key and leaves state unchanged', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.addUserCommand.runAsync((name: 'Alice', publicKeyBase64Url: 'not-a-key')));
      await settleErrors(h.controller.addUserCommand);

      expect(h.controller.addUserCommand.errors.value, isNotNull);
      expect(h.controller.addUserCommand.errors.value!.error, isA<UserDeviceError>());
      expect(h.controller.state.value!.users!.users, hasLength(1));
    });
  });

  group('revokeUserCommand —', () {
    test('tombstones a member', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();
      await h.controller.addUserCommand.runAsync((name: 'Alice', publicKeyBase64Url: validPublicKey(1)));
      final aliceId = h.controller.state.value!.users!.users.firstWhere((u) => u.name == 'Alice').userId;

      await h.controller.revokeUserCommand.runAsync(aliceId);

      expect(h.controller.revokeUserCommand.errors.value, isNull);
      final alice = h.controller.state.value!.users!.usersById[aliceId]!;
      expect(alice.isRemoved, isTrue);
    });

    test('refuses to revoke the owner', () async {
      final (h, result) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.revokeUserCommand.runAsync(result.owner.userId));
      await settleErrors(h.controller.revokeUserCommand);

      expect(h.controller.revokeUserCommand.errors.value, isNotNull);
      expect(h.controller.revokeUserCommand.errors.value!.error, isA<UserDeviceError>());
      expect(h.controller.state.value!.users!.usersById[result.owner.userId]!.isRemoved, isFalse);
    });
  });

  group('revokeDeviceCommand —', () {
    test('tombstones a device in the operator registry', () async {
      final (h, result) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await h.controller.revokeDeviceCommand.runAsync(result.device.uuid);

      expect(h.controller.revokeDeviceCommand.errors.value, isNull);
      final device = h.controller.state.value!.devices!.devicesById[result.device.uuid]!;
      expect(device.isRemoved, isTrue);
    });

    test('rejects an unknown device', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.revokeDeviceCommand.runAsync('unknown-device-uuid'));
      await settleErrors(h.controller.revokeDeviceCommand);

      expect(h.controller.revokeDeviceCommand.errors.value, isNotNull);
      expect(h.controller.revokeDeviceCommand.errors.value!.error, isA<UserDeviceError>());
    });
  });

  group('renameDeviceCommand —', () {
    test('renames the local device and persists it', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await h.controller.renameDeviceCommand.runAsync('My Laptop');

      expect(h.controller.renameDeviceCommand.errors.value, isNull);
      expect(h.controller.state.value!.device!.name, 'My Laptop');
      // Persisted to .noetec/device.json (the source of truth across opens).
      final device = await h.deviceService.ensureDevice(UserDeviceHarness.root, UserDeviceHarness.vaultId);
      expect(device.name, 'My Laptop');
    });

    test('rejects an empty name', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.renameDeviceCommand.runAsync('   '));
      await settleErrors(h.controller.renameDeviceCommand);

      expect(h.controller.renameDeviceCommand.errors.value, isNotNull);
      expect(h.controller.state.value!.device!.name, isNot(''));
    });
  });

  group('showSeed —', () {
    test('reconstructs the 24-word mnemonic from secure storage', () async {
      final (h, result) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      final seed = await h.controller.showSeed();
      expect(seed, isNotNull);
      expect(seed, result.mnemonic);
      expect(seed!.split(' ').length, 24);
      expect(bip39.validateMnemonic(seed), isTrue);
    });

    test('returns null when the vault has no identity', () async {
      final h = await buildUserDeviceHarness();

      expect(await h.controller.showSeed(), isNull);
    });
  });

  group('state —', () {
    test('resets to null when the vault closes', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();
      expect(h.controller.state.value, isNotNull);

      h.vault.currentVault.value = null;
      expect(h.controller.state.value, isNull);
    });
  });

  group('bootstrap/restore affordances —', () {
    test('canBootstrapOwner is true for an un-onboarded vault', () async {
      final h = await buildUserDeviceHarness();
      await h.controller.refreshCommand.runAsync();

      // No identity and no users.json: the vault has no owner yet.
      expect(h.controller.canBootstrapOwner, isTrue);
      expect(h.controller.canRestoreIdentity, isFalse);
    });

    test('canRestoreIdentity is true when users.json exists but there is no local identity', () async {
      // Device A: create an on-boarded vault (owner + registries).
      final a = await buildOnboardedHarness();
      // Device B: same synced registry, but a fresh machine (no identity, no
      // local device) — the "restore from seed" case.
      final b = await buildFreshDeviceOf(a.$1, a.$2.owner.userId);
      await b.controller.refreshCommand.runAsync();

      expect(b.controller.state.value!.operator, isNull);
      expect(b.controller.state.value!.users, isNotNull);
      expect(b.controller.canBootstrapOwner, isFalse);
      expect(b.controller.canRestoreIdentity, isTrue);
    });

    test('both are false once the operator is onboarded', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      expect(h.controller.canBootstrapOwner, isFalse);
      expect(h.controller.canRestoreIdentity, isFalse);
    });
  });

  group('bootstrapOwnerCommand —', () {
    test('creates the owner identity + registries and returns the 24-word seed', () async {
      final h = await buildUserDeviceHarness();
      await h.controller.refreshCommand.runAsync();

      final mnemonic = await h.controller.bootstrapOwnerCommand.runAsync((ownerName: 'Owner', deviceName: 'My Device'));

      // The one-time backup seed is returned (24 BIP39 words) ...
      expect(bip39.validateMnemonic(mnemonic), isTrue);
      expect(mnemonic.split(' ').length, 24);
      // ... and the snapshot now shows the owner + populated registries.
      final snapshot = h.controller.state.value!;
      expect(snapshot.operator, isNotNull);
      expect(snapshot.operator!.name, 'Owner');
      expect(snapshot.operator!.role, 'owner');
      expect(snapshot.users, isNotNull);
      expect(snapshot.users!.ownerUserId, snapshot.operator!.userId);
      expect(snapshot.users!.users, hasLength(1));
      expect(snapshot.devices, isNotNull);
      expect(snapshot.devices!.devices, hasLength(1));
      // The identity is persisted to disk.
      expect(h.fs.files.containsKey('${UserDeviceHarness.root}/.noetec/identity.json'), isTrue);
      // The one-time seed is NOT stored in reactive state.
      expect(snapshot.operator?.toString().contains(mnemonic), isFalse);
    });

    test('rejects an empty owner name', () async {
      final h = await buildUserDeviceHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.bootstrapOwnerCommand.runAsync((ownerName: '   ', deviceName: null)));
      await settleErrors(h.controller.bootstrapOwnerCommand);

      expect(h.controller.bootstrapOwnerCommand.errors.value, isNotNull);
      expect(h.controller.bootstrapOwnerCommand.errors.value!.error, isA<UserDeviceError>());
      expect(h.controller.state.value!.operator, isNull);
    });

    test('refuses to bootstrap a vault that already has an owner', () async {
      final (h, _) = await buildOnboardedHarness();
      await h.controller.refreshCommand.runAsync();

      await runSwallow(() => h.controller.bootstrapOwnerCommand.runAsync((ownerName: 'Sneaky', deviceName: null)));
      await settleErrors(h.controller.bootstrapOwnerCommand);

      expect(h.controller.bootstrapOwnerCommand.errors.value, isNotNull);
      final err = h.controller.bootstrapOwnerCommand.errors.value!.error as UserDeviceError;
      expect(err.message, 'This vault already has an owner.');
      // The original owner is unchanged.
      expect(h.controller.state.value!.users!.users, hasLength(1));
    });
  });

  group('restoreIdentityCommand —', () {
    test('restores the identity from the seed and binds the device', () async {
      final (h, result) = await buildOnboardedHarness();
      // A fresh machine: same synced registry, no local identity/device.
      final b = await buildFreshDeviceOf(h, result.owner.userId);

      await b.controller.restoreIdentityCommand.runAsync((mnemonic: result.mnemonic, deviceName: null));

      expect(b.controller.restoreIdentityCommand.errors.value, isNull);
      final snapshot = b.controller.state.value!;
      // The restored identity matches the owner by public key / userId.
      expect(snapshot.operator, isNotNull);
      expect(snapshot.operator!.userId, result.owner.userId);
      expect(snapshot.operator!.publicKey, result.owner.publicKey);
      // The local device is bound (a certificate in the operator's registry).
      expect(snapshot.devices, isNotNull);
      expect(snapshot.devices!.devices, isNotEmpty);
      expect(b.fs.files.containsKey('${UserDeviceHarness.root}/.noetec/identity.json'), isTrue);
    });

    test('rejects an empty seed', () async {
      final (h, result) = await buildOnboardedHarness();
      final b = await buildFreshDeviceOf(h, result.owner.userId);
      await b.controller.refreshCommand.runAsync();

      await runSwallow(() => b.controller.restoreIdentityCommand.runAsync((mnemonic: '   ', deviceName: null)));
      await settleErrors(b.controller.restoreIdentityCommand);

      expect(b.controller.restoreIdentityCommand.errors.value, isNotNull);
      expect(b.controller.restoreIdentityCommand.errors.value!.error, isA<UserDeviceError>());
      expect(b.controller.state.value!.operator, isNull);
    });
  });
}
