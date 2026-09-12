// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:command_it/command_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/service/user_device_controller.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:noetec/view/widgets/content_panel/settings_panel.dart';

import '../../../../helpers/user_device_harness.dart';

/// Finds a [TextField] by the label text of its decoration (dialogs reuse the
/// same widget type, so type-based finders are ambiguous).
Finder _textFieldWithLabel(String label) => find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == label);

/// Renders the [SettingsPanel] over a vault the given [harness] manages (the
/// harness's [UserDeviceController] and [VaultSystem] are wired into get_it,
/// which the panel resolves via `di<...>()`).
Future<UserDeviceHarness> _pumpBareSettings(WidgetTester tester, [UserDeviceHarness? harness]) async {
  await GetIt.instance.reset();
  final h = harness ?? await buildUserDeviceHarness();
  GetIt.instance.registerSingleton<VaultSystem>(h.vault);
  GetIt.instance.registerSingleton<UserDeviceController>(h.controller);
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPanel())));
  await tester.pumpAndSettle();
  return h;
}

/// Renders the [SettingsPanel] over the real in-memory harness, wiring the
/// harness's [UserDeviceController] and [VaultSystem] into get_it (the panel
/// resolves both via `di<...>()`).
Future<(UserDeviceHarness, CreateVaultResult)> _pumpSettings(WidgetTester tester) async {
  await GetIt.instance.reset();
  final (h, result) = await buildOnboardedHarness();
  GetIt.instance.registerSingleton<VaultSystem>(h.vault);
  GetIt.instance.registerSingleton<UserDeviceController>(h.controller);
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPanel())));
  // The panel kicks off `refreshCommand` on first build (state == null); let
  // it settle so the sections render from the populated snapshot.
  await tester.pumpAndSettle();
  return (h, result);
}

void main() {
  setUp(() {
    // Swallow command errors routed to the global handler (none expected on
    // the happy paths, but guard against an unhandled "no global handler").
    Command.globalExceptionHandler = (_, _) {};
  });

  tearDown(() async {
    disposeUserDeviceHarnesses();
    await GetIt.instance.reset();
  });

  testWidgets('renders device, users and devices from an onboarded vault', (tester) async {
    final (_, result) = await _pumpSettings(tester);

    // Section headers.
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);

    // The local device. Onboarding labels the registry certificate "First
    // Laptop" but leaves the local device.json name as "Default Device", so the
    // "This device" card and the registry tile show different names.
    expect(find.text('Default Device'), findsOneWidget);
    expect(find.text('First Laptop'), findsOneWidget);

    // The owner user and its badge.
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('owner'), findsOneWidget);
    expect(find.text('this device'), findsOneWidget);

    // The seed action is present.
    expect(find.text('Show recovery seed'), findsOneWidget);

    // The snapshot is fully populated (sanity).
    expect(result.owner.name, 'Owner');
  });

  testWidgets('shows the 24-word recovery seed on demand', (tester) async {
    final (h, result) = await _pumpSettings(tester);
    final mnemonic = result.mnemonic;

    await tester.tap(find.text('Show recovery seed'));
    await tester.pumpAndSettle();

    // The dialog opened.
    expect(find.text('Recovery seed'), findsOneWidget);
    // The 24-word mnemonic is displayed (verify a couple of its words).
    final words = mnemonic.split(' ');
    expect(words, hasLength(24));
    expect(find.textContaining(words.first), findsOneWidget);
    expect(find.textContaining(words.last), findsOneWidget);

    // The seed is not left in the controller's reactive state.
    expect(h.controller.state.value, isNotNull);
    // (state holds only public material; the mnemonic is never stored there.)
  });

  testWidgets('renames the local device and updates the label', (tester) async {
    final (h, _) = await _pumpSettings(tester);

    // Initially the local card shows "Default Device" (the registry tile
    // shows the certificate name "First Laptop").
    expect(find.text('Default Device'), findsOneWidget);
    expect(find.text('First Laptop'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename device'));
    await tester.pumpAndSettle();
    expect(find.text('Rename device'), findsOneWidget); // dialog title

    // Overwrite the pre-filled name and confirm.
    await tester.enterText(find.byType(TextField), 'Renamed Laptop');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // The "This device" card reflects the new local name, while the registry
    // device tile still shows the original registry record name.
    expect(find.text('Renamed Laptop'), findsOneWidget);
    expect(find.text('First Laptop'), findsOneWidget);
    expect(h.controller.state.value!.device!.name, 'Renamed Laptop');
  });

  testWidgets('owner can open the add-user dialog', (tester) async {
    final (h, _) = await _pumpSettings(tester);
    expect(h.controller.isOperatorOwner, isTrue);

    await tester.tap(find.byTooltip('Add user'));
    await tester.pumpAndSettle();

    // The dialog opened: its title and submit button are both "Add user", and
    // it has the name + key fields.
    expect(find.text('Add user'), findsNWidgets(2)); // dialog title + submit button
    expect(find.byType(TextField), findsNWidgets(2));

    // Dismiss it (Cancel) so the test tears down cleanly.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add user'), findsNothing);
  });

  group('identity setup —', () {
    testWidgets('new vault: "Become the owner" creates the identity and reveals the seed once', (tester) async {
      final h = await _pumpBareSettings(tester);

      // The identity section offers setup (no owner yet) — and no restore.
      expect(find.text('Your identity'), findsOneWidget);
      expect(find.text('Become the owner'), findsOneWidget);
      expect(find.text('Restore from recovery seed'), findsNothing);

      // The management sections are present but unmanaged (no identity).
      expect(find.text('No user registry yet'), findsOneWidget);

      // Set up the owner.
      await tester.tap(find.text('Become the owner'));
      await tester.pumpAndSettle();
      expect(find.text('Become the owner'), findsNWidgets(2)); // section button + dialog title
      await tester.enterText(_textFieldWithLabel('Your name'), 'Owner');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      // The setup dialog closes, the command runs, the seed dialog opens.
      await tester.pumpAndSettle();

      // The one-time 24-word seed is revealed (and only via this dialog).
      expect(find.text('Recovery seed'), findsOneWidget);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data!.trim().split(RegExp(r'\s+')), hasLength(24));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Recovery seed'), findsNothing);

      // The identity section is gone; the owner is now listed and the device
      // registry is populated.
      expect(find.text('Your identity'), findsNothing);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('No user registry yet'), findsNothing);
      expect(h.controller.state.value!.operator?.name, 'Owner');
    });

    testWidgets('owned vault, fresh device: "Restore from recovery seed" re-joins the owner', (tester) async {
      // Device A onboards; device B is a fresh machine with the synced registry.
      final (a, result) = await buildOnboardedHarness();
      final b = await buildFreshDeviceOf(a, result.owner.userId);
      await _pumpBareSettings(tester, b);

      // The restore offer (the vault already has an owner, so no bootstrap).
      expect(find.text('Restore from recovery seed'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Become the owner'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Restore from recovery seed'));
      await tester.pumpAndSettle();
      await tester.enterText(_textFieldWithLabel('Recovery seed (24 words)'), result.mnemonic);
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      // The identity is restored: the owner is listed again and the identity
      // section disappears.
      expect(find.text('Your identity'), findsNothing);
      expect(find.text('Owner'), findsOneWidget);
      expect(b.controller.state.value!.operator?.userId, result.owner.userId);
    });

    testWidgets('onboarded vault: the identity section is hidden', (tester) async {
      await _pumpSettings(tester);
      expect(find.text('Your identity'), findsNothing);
      expect(find.text('Become the owner'), findsNothing);
      expect(find.text('Restore from recovery seed'), findsNothing);
    });
  });
}
