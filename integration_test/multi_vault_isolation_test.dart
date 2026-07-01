import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/key_assertions.dart';
import 'helpers/session_assertions.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// E2E Scenario: User creates two different vaults sequentially, closes and
  /// reopens one. Verify that each vault has its own identity, session data
  /// stays isolated, and no pages leak between vaults.
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
      /* Arrange: launch the app shell */
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      // Act: create Vault Alpha
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'VaultAlpha');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultAlphaPath = p.join(parentDir.rootPath, 'VaultAlpha');

      // Assert: Alpha session has welcome page
      await expectSessionJsonValid(
        vaultAlphaPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

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
      await expectSessionJsonValid(
        vaultBetaPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Assert: each vault has a unique ID
      final alphaVaultId = await readVaultId(vaultAlphaPath);
      final betaVaultId = await readVaultId(vaultBetaPath);
      expect(alphaVaultId, isNot(equals(betaVaultId)));

      // Assert: Alpha's session.json does not contain Beta's pages
      final alphaSessionFile = File(
        p.join(vaultAlphaPath, '.noetec', 'session.json'),
      );
      final alphaRaw = await alphaSessionFile.readAsString();
      final alphaContent = jsonDecode(alphaRaw) as Map<String, dynamic>;
      final alphaOpenPages = (alphaContent['open_pages'] as List)
          .cast<String>();
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
      final alphaRestoredPaths = pageSystem.openPages.values
          .map((e) => e.relativePath)
          .toSet();
      expect(alphaRestoredPaths, contains('pages/welcome.md'));
      expect(alphaRestoredPaths, isNot(contains('pages/beta-b.md')));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
