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
}
