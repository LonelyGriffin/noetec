import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/key_assertions.dart';
import 'helpers/session_assertions.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_assertions.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vault creation good-path', (tester) async {
    final fileSystem = TestFileSystemService();
    final settings = InMemorySettingsService();
    final secureKeyStore = InMemorySecureKeyStore();
    final parentDir = await VaultFolderFixture.createEmpty();
    fileSystem.nextPickPath = parentDir.rootPath;

    await configureDI(
      fileSystem: fileSystem,
      settings: settings,
      secureKeyStore: secureKeyStore,
    );

    try {
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      // Create vault through UI
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'FlowVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'FlowVault');

      await expectSessionJsonExists(vaultPath);
      await expectVaultJsonValid(vaultPath, name: 'FlowVault');
      await expectDeviceIdentityExists(vaultPath);
      await expectDeviceHasPublicKey(vaultPath);

      final devicePrivateKey = await readDevicePrivateKeyFromStore(vaultPath);
      expect(devicePrivateKey, isNotNull);
      expect(devicePrivateKey, isNotEmpty);

      expect(
        await File(p.join(vaultPath, 'pages', 'welcome.md')).exists(),
        isTrue,
      );

      // Check record in recent vaults list
      final recentRaw = await settings.getString('noetec.recent_vaults');
      expect(recentRaw, isNotNull);
      final recentVaults = json.decode(recentRaw!) as List<dynamic>;
      expect(
        recentVaults.any(
          (item) => (item as Map<String, dynamic>)['rootPath'] == vaultPath,
        ),
        isTrue,
      );

      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // UI: Close vault via Settings panel "Open Another Vault"
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      final openAnotherButton = findOpenAnotherVaultButton();
      await tester.ensureVisible(openAnotherButton);
      await tester.tap(openAnotherButton);
      await tester.pumpAndSettle();

      final pageSystem = GetIt.instance<PageSystem>();
      final vaultSystem = GetIt.instance<VaultSystem>();
      expect(pageSystem.openPages, isEmpty);
      expect(pageSystem.activePageId.value, isNull);
      expect(vaultSystem.currentVault.value, isNull);

      // UI: reopen vault from recent vaults list
      await tester.tap(findRecentVaultEntry('FlowVault'));
      await tester.pumpAndSettle();

      // After reopening: session.json exists, but PageSystem.restoreSession is
      // async (unawaited) so `pumpAndSettle` may not wait for it yet.
      // This is expected to fail until implementation is in place.
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Verify pages were restored in PageSystem
      expect(pageSystem.openPages.length, equals(1));
      final restoredPaths = pageSystem.openPages.values
          .map((e) => e.relativePath!)
          .toSet();
      expect(restoredPaths, contains('pages/welcome.md'));

      expect(
        pageSystem.getActivePage()!.relativePath,
        equals('pages/welcome.md'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });

  testWidgets('Multi-vault session isolation', (tester) async {
    final fileSystem = TestFileSystemService();
    final settings = InMemorySettingsService();
    final secureKeyStore = InMemorySecureKeyStore();
    final parentDir = await VaultFolderFixture.createEmpty();
    fileSystem.nextPickPath = parentDir.rootPath;

    await configureDI(
      fileSystem: fileSystem,
      settings: settings,
      secureKeyStore: secureKeyStore,
    );

    try {
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      // Create Vault Alpha
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'VaultAlpha');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultAlphaPath = p.join(parentDir.rootPath, 'VaultAlpha');

      await expectSessionJsonValid(
        vaultAlphaPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // UI: Close vault via Settings panel
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findOpenAnotherVaultButton());
      await tester.tap(findOpenAnotherVaultButton());
      await tester.pumpAndSettle();

      // Create Vault Beta
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'VaultBeta');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultBetaPath = p.join(parentDir.rootPath, 'VaultBeta');

      await expectSessionJsonValid(
        vaultBetaPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Alpha's session.json should NOT contain Beta's pages
      final alphaSessionFile = File(
        p.join(vaultAlphaPath, '.noetec', 'session.json'),
      );
      final alphaRaw = await alphaSessionFile.readAsString();
      final alphaContent = jsonDecode(alphaRaw) as Map<String, dynamic>;
      final alphaOpenPages = (alphaContent['open_pages'] as List)
          .cast<String>();
      expect(alphaOpenPages, contains('pages/welcome.md'));
      expect(alphaOpenPages, isNot(contains('pages/beta-b.md')));

      // UI: close Beta vault via Settings panel
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findOpenAnotherVaultButton());
      await tester.tap(findOpenAnotherVaultButton());
      await tester.pumpAndSettle();

      // UI: reopen Alpha from recent vaults list
      await tester.tap(findRecentVaultEntry('VaultAlpha'));
      await tester.pumpAndSettle();

      final pageSystem = GetIt.instance<PageSystem>();
      // Alpha should restore only its own pages, no Beta pages leaked
      final alphaRestoredPaths = pageSystem.openPages.values
          .map((e) => e.relativePath!)
          .toSet();
      expect(alphaRestoredPaths, contains('pages/welcome.md'));
      expect(alphaRestoredPaths, isNot(contains('pages/beta-b.md')));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });

  testWidgets('Page tab management and session persistence', (tester) async {
    final fileSystem = TestFileSystemService();
    final settings = InMemorySettingsService();
    final secureKeyStore = InMemorySecureKeyStore();
    final parentDir = await VaultFolderFixture.createEmpty();
    fileSystem.nextPickPath = parentDir.rootPath;

    await configureDI(
      fileSystem: fileSystem,
      settings: settings,
      secureKeyStore: secureKeyStore,
    );

    try {
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      // Create vault
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'TabVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'TabVault');

      // Verify welcome tab is open in editor
      expect(findTabWithTitle('welcome'), findsOneWidget);

      // Verify initial session with welcome.md
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Create extra.md via Pages panel
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.tap(findNewPageButton());
      await tester.pumpAndSettle();

      await tester.enterText(findPageRenameField(), 'extra');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Open extra.md from Pages panel
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      // Verify session with both pages
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md', 'pages/extra.md'],
        expectedActivePagePath: 'pages/extra.md',
      );

      // Close extra.md tab via UI
      await tester.tap(findTabCloseButton('extra'));
      await tester.pumpAndSettle();

      // Verify extra tab is gone, welcome tab still present
      expect(findTabWithTitle('extra'), findsNothing);
      expect(findTabWithTitle('welcome'), findsOneWidget);

      // Verify session updated
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Close welcome.md tab via UI
      await tester.tap(findTabCloseButton('welcome'));
      await tester.pumpAndSettle();

      // Verify empty editor state
      expect(find.text('Open a page to start editing'), findsOneWidget);

      // Verify session is empty
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: [],
        expectedActivePagePath: null,
      );

      // Reopen extra.md via Pages panel (panel is already open)
      expect(findPageInPanel('extra.md'), findsOneWidget);
      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      // Verify tab is present
      expect(findTabWithTitle('extra'), findsOneWidget);

      // Verify session updated
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/extra.md'],
        expectedActivePagePath: 'pages/extra.md',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
