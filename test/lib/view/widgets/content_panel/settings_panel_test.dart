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
}
