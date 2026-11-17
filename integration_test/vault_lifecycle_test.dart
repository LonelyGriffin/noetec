// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/key_assertions.dart';
import 'helpers/pump_test_app.dart';
import 'helpers/session_assertions.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_assertions.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Vault lifecycle', () {
    /// E2E Scenario: User creates a new vault, verifies all expected files
    /// and keys are generated, then closes and reopens the vault from the
    /// recent vaults list to confirm session state is restored.
    testWidgets('Vault creation good-path', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        /* Arrange: launch the app shell */
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        // Act: create vault through UI
        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'FlowVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'FlowVault');

        // Assert: vault infrastructure files exist
        await expectSessionJsonExists(vaultPath);
        await expectVaultJsonValid(vaultPath, name: 'FlowVault');
        await expectDeviceIdentityExists(vaultPath);
        await expectDeviceHasPublicKey(vaultPath);

        final devicePrivateKey = await readDevicePrivateKeyFromStore(vaultPath);
        expect(devicePrivateKey, isNotNull);
        expect(devicePrivateKey, isNotEmpty);

        expect(await File(p.join(vaultPath, 'pages', 'welcome.md')).exists(), isTrue);

        await expectPageFileValid(vaultPath, 'pages/welcome.md');

        // Assert: vault recorded in recent vaults settings
        final recentRaw = await settings.getString('noetec.recent_vaults');
        expect(recentRaw, isNotNull);
        final recentVaults = json.decode(recentRaw!) as List<dynamic>;
        expect(recentVaults.any((item) => (item as Map<String, dynamic>)['rootPath'] == vaultPath), isTrue);

        // Assert: session state tracks welcome page as open and active
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        expect(await Directory(p.join(vaultPath, '.sync', 'pages')).exists(), isTrue);

        await expectOpLogExists(vaultPath, 'pages/welcome.md');

        // Act: close vault via Settings panel "Open Another Vault"
        await tester.tap(findSettingsPanelButton());
        await tester.pumpAndSettle();

        final openAnotherButton = findOpenAnotherVaultButton();
        await tester.ensureVisible(openAnotherButton);
        await tester.tap(openAnotherButton);
        await tester.pumpAndSettle();

        // Assert: in-memory state is cleared after close
        final pageSystem = GetIt.instance<PageSystem>();
        final vaultSystem = GetIt.instance<VaultSystem>();
        expect(pageSystem.openPages, isEmpty);
        expect(pageSystem.activePageId.value, isNull);
        expect(vaultSystem.currentVault.value, isNull);

        // Act: reopen vault from recent vaults list
        await tester.tap(findRecentVaultEntry('FlowVault'));
        await tester.pumpAndSettle();

        // Assert: session.json still valid after reopen
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        // Assert: pages were restored in PageSystem
        expect(pageSystem.openPages.length, equals(1));
        final restoredPaths = pageSystem.openPages.values.map((e) => e.relativePath).toSet();
        expect(restoredPaths, contains('pages/welcome.md'));

        expect(pageSystem.getActivePage()!.relativePath, equals('pages/welcome.md'));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    /// E2E Scenario: User types text into the welcome page, saves, then closes
    /// and reopens the vault. After reopening, verify that the edited content is
    /// restored in memory and that the on-disk file hash matches the saved hash.
    testWidgets('Edited content persists after closing and reopening vault', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        /* Arrange: launch the app shell */
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        // Act: create vault
        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'PersistVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'PersistVault');

        // Act: focus editor and type "hello"
        await tester.tap(findEditorBlock());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);

        // Allow auto-save debounce to flush
        await tester.pump(const Duration(milliseconds: 500));

        // Assert: tab shows unsaved indicator (circle icon) before save
        expect(findTabUnsavedIndicator('welcome'), findsOneWidget, reason: 'Tab should show unsaved indicator before Ctrl+S');

        // Act: save with Ctrl+S
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        // Assert: unsaved indicator disappears after save
        expect(findTabUnsavedIndicator('welcome'), findsNothing, reason: 'Tab should not show unsaved indicator after Ctrl+S');

        // Arrange: capture hash after save
        final hashAfterSave = await readContentHash(vaultPath, 'pages/welcome.md');

        // Act: close vault via Settings panel
        await tester.tap(findSettingsPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findOpenAnotherVaultButton());
        await tester.tap(findOpenAnotherVaultButton());
        await tester.pumpAndSettle();

        // Assert: in-memory state cleared
        final pageSystem = GetIt.instance<PageSystem>();
        expect(pageSystem.openPages, isEmpty);

        // Assert: welcome file on disk still contains "hello"
        final welcomeContent = await File(p.join(vaultPath, 'pages', 'welcome.md')).readAsString();
        expect(welcomeContent, contains('hello'));

        // Act: reopen vault from recent vaults
        await tester.tap(findRecentVaultEntry('PersistVault'));
        await tester.pumpAndSettle();

        // Assert: pages restored in memory
        expect(pageSystem.openPages, isNotEmpty);
        final restoredBlock = pageSystem.getActivePage()!.rootBlocks.whereType<TextBlockEntity>().first;
        expect(restoredBlock.computeAllSegmentsText(), contains('hello'));

        // Assert: file hash unchanged after reopen (content was saved)
        final hashAfterReopen = await readContentHash(vaultPath, 'pages/welcome.md');
        expect(hashAfterReopen, equals(hashAfterSave));

        // Assert: no unsaved indicator since content was saved before closing
        expect(findTabUnsavedIndicator('welcome'), findsNothing, reason: 'Tab should not show unsaved indicator (content was saved)');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    /// E2E Scenario: User creates two different vaults sequentially, closes and
    /// reopens one. Verify that each vault has its own identity, session data
    /// stays isolated, and no pages leak between vaults.
    testWidgets('Multi-vault session isolation', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        /* Arrange: launch the app shell */
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        // Act: create Vault Alpha
        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'VaultAlpha');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultAlphaPath = p.join(parentDir.rootPath, 'VaultAlpha');

        // Assert: Alpha session has welcome page
        await expectSessionJsonValid(vaultAlphaPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        // Act: close Alpha via Settings panel
        await tester.tap(findSettingsPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findOpenAnotherVaultButton());
        await tester.tap(findOpenAnotherVaultButton());
        await tester.pumpAndSettle();

        // Act: create Vault Beta
        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'VaultBeta');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultBetaPath = p.join(parentDir.rootPath, 'VaultBeta');

        // Assert: Beta session has its own welcome page
        await expectSessionJsonValid(vaultBetaPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        // Assert: each vault has a unique ID
        final alphaVaultId = await readVaultId(vaultAlphaPath);
        final betaVaultId = await readVaultId(vaultBetaPath);
        expect(alphaVaultId, isNot(equals(betaVaultId)));

        // Assert: Alpha's session.json does not contain Beta's pages
        final alphaSessionFile = File(p.join(vaultAlphaPath, '.noetec', 'session.json'));
        final alphaRaw = await alphaSessionFile.readAsString();
        final alphaContent = jsonDecode(alphaRaw) as Map<String, dynamic>;
        final alphaOpenPages = (alphaContent['open_pages'] as List).cast<String>();
        expect(alphaOpenPages, contains('pages/welcome.md'));
        expect(alphaOpenPages, isNot(contains('pages/beta-b.md')));

        // Act: close Beta vault via Settings panel
        await tester.tap(findSettingsPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findOpenAnotherVaultButton());
        await tester.tap(findOpenAnotherVaultButton());
        await tester.pumpAndSettle();

        // Act: reopen Alpha from recent vaults list
        await tester.tap(findRecentVaultEntry('VaultAlpha'));
        await tester.pumpAndSettle();

        // Assert: Alpha restores only its own pages, no Beta leakage
        final pageSystem = GetIt.instance<PageSystem>();
        final alphaRestoredPaths = pageSystem.openPages.values.map((e) => e.relativePath).toSet();
        expect(alphaRestoredPaths, contains('pages/welcome.md'));
        expect(alphaRestoredPaths, isNot(contains('pages/beta-b.md')));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });
  });
}
