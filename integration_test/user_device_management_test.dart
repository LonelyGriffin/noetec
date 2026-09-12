// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

/// Drives the REAL app (`MainApp` + real DI + real services) and verifies the
/// user-facing behavior of the NOET-33 user & device management panel from the
/// user's perspective.
///
/// Two scenarios:
///  - "fresh vault"  — a real user creating a vault through the UI, with NO
///    onboarding. Documents that the identity/registries are never created, so
///    add/revoke/seed are unreachable (the user cannot exercise the core
///    acceptance criteria).
///  - "on-boarded"   — the same panel given an on-boarded vault, proving the
///    NOET-33 UI (rename / add user / revoke / show seed) is correct.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A valid 32-byte base64url Ed25519 public key (for "add user").
  String validPublicKey(int seed) => base64UrlEncode(List<int>.generate(32, (i) => (seed + i * 7) & 0xff));

  /// Bounded pump-until (integration tests on WSL are timing-sensitive).
  Future<void> pumpUntil(WidgetTester tester, bool Function() cond, {Duration timeout = const Duration(seconds: 30), required String what}) async {
    final sw = Stopwatch()..start();
    while (!cond()) {
      if (sw.elapsed > timeout) {
        throw StateError('pumpUntil timed out waiting for: $what');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Creates a vault through the real UI and returns its path.
  Future<String> createVaultViaUi(WidgetTester tester, TestFileSystemService fs, String vaultName) async {
    await tester.tap(findCreateVaultButton());
    await tester.pumpAndSettle();
    await tester.enterText(findVaultNameField(), vaultName);
    await tester.tap(findDialogCreateButton());
    // Wait for the async create command to open the vault (router -> /editor).
    await pumpUntil(tester, () => GetIt.instance<VaultSystem>().currentVault.value != null, what: 'vault to open');
    return p.join(fs.nextPickPath!, vaultName);
  }

  /// Navigates to the settings panel and waits for it to populate.
  Future<void> openSettingsAndWait(WidgetTester tester) async {
    await tester.tap(findSettingsPanelButton());
    // The panel refreshes on first build; wait for the section titles to appear.
    await pumpUntil(tester, () => find.text('Users').evaluate().isNotEmpty && find.text('Devices').evaluate().isNotEmpty, what: 'settings panel to populate');
  }

  group('NOET-33 user & device management (real app)', () {
    late TestFileSystemService fileSystem;
    late InMemorySecureKeyStore secureKeyStore;
    late VaultFolderFixture parent;

    setUp(() async {
      fileSystem = TestFileSystemService();
      secureKeyStore = InMemorySecureKeyStore();
      parent = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parent.rootPath;
      await configureDI(fileSystem: fileSystem, settings: InMemorySettingsService(), secureKeyStore: secureKeyStore);
    });

    tearDown(() async {
      await GetIt.instance.reset();
      await parent.dispose();
    });

    testWidgets('fresh vault: identity/registries are never created, so management is unreachable', (tester) async {
      // Desktop-sized surface (IconRail layout, width >= 720).
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      final vaultPath = await createVaultViaUi(tester, fileSystem, 'GapVault');
      await openSettingsAndWait(tester);

      // The device exists (createVault always ensures one) ...
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Default Device'), findsOneWidget);

      // ... but there is NO user registry and NO device registry.
      expect(find.text('No user registry yet'), findsOneWidget, reason: 'users.json is never created for a real user-created vault');
      expect(find.text('No device registry yet'), findsOneWidget, reason: 'devices/<ownerId>.json is never created');

      // The "Add user" action is only available to the owner; there is no
      // operator identity, so the button is absent.
      expect(find.byTooltip('Add user'), findsNothing, reason: 'no owner identity -> cannot add users');

      // "Show recovery seed" is present (the device card shows it) but there is
      // no identity, so it cannot display a seed: tapping it opens no dialog.
      expect(find.widgetWithText(OutlinedButton, 'Show recovery seed'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Show recovery seed'));
      await tester.pumpAndSettle();
      expect(find.text('Recovery seed'), findsNothing, reason: 'no identity -> no seed can be shown');

      // On-disk proof: no identity.json, no users.json, no device registry.
      expect(await File(p.join(vaultPath, '.noetec', 'identity.json')).exists(), isFalse, reason: 'identity is never created for a real user');
      expect(await File(p.join(vaultPath, '.sync', 'users.json')).exists(), isFalse, reason: 'users.json is never created');
      expect(await Directory(p.join(vaultPath, '.sync', 'devices')).exists(), isFalse, reason: 'device registry is never created');
    });

    testWidgets('on-boarded vault: rename / add user / revoke / show seed all work', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      final vaultPath = await createVaultViaUi(tester, fileSystem, 'OnboardVault');

      // Onboard the vault (identity + registries) the way NOET-32's service does.
      // This is the state the NOET-33 panel is designed to manage.
      final onboarding = GetIt.instance<IOnboardingService>();
      await onboarding.createVaultOnboarding(ownerName: 'Owner', deviceName: 'First Laptop');

      await openSettingsAndWait(tester);

      // The owner user and the local device are now listed.
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('owner'), findsWidgets, reason: 'owner badge');
      expect(find.text('First Laptop'), findsWidgets, reason: 'local device listed');
      expect(find.text('No user registry yet'), findsNothing);
      expect(find.text('No device registry yet'), findsNothing);

      // --- Show recovery seed (on demand, 24 words) ---
      await tester.tap(find.widgetWithText(OutlinedButton, 'Show recovery seed'));
      await tester.pumpAndSettle();
      expect(find.text('Recovery seed'), findsOneWidget);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      final words = selectable.data!.trim().split(RegExp(r'\s+'));
      expect(words.length, 24, reason: 'BIP39 24-word mnemonic shown on demand');
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      // --- Rename the current device (user-editable, persisted) ---
      await tester.tap(find.byTooltip('Rename device'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'My Laptop');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await pumpUntil(tester, () => find.text('My Laptop').evaluate().isNotEmpty, what: 'renamed device name');
      // Persisted to device.json.
      final deviceJson = json.decode(await File(p.join(vaultPath, '.noetec', 'device.json')).readAsString()) as Map<String, dynamic>;
      expect(deviceJson['name'], 'My Laptop');

      // --- Add a user by public key ---
      await tester.tap(find.byTooltip('Add user'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == "Alice's key"), 'Alice');
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Ed25519 identity key'), validPublicKey(1));
      await tester.tap(find.widgetWithText(FilledButton, 'Add user'));
      await pumpUntil(tester, () => find.text('Alice').evaluate().isNotEmpty, what: 'added user');

      // --- Revoke the added user ---
      // The revoke button is the person_remove icon on Alice's tile.
      final aliceTile = find.ancestor(of: find.text('Alice'), matching: find.byType(Card)).first;
      await tester.tap(find.descendant(of: aliceTile, matching: find.byTooltip('Revoke user')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await pumpUntil(tester, () => find.text('Revoked').evaluate().isNotEmpty, what: 'revoked user state');

      // On-disk proof: the new user record is in users.json.
      final usersRaw = await File(p.join(vaultPath, '.sync', 'users.json')).readAsString();
      expect(usersRaw, contains('Alice'));
    });
  });
}
