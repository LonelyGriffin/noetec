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

  /// E2E Scenario: User creates a new vault, verifies all expected files
  /// and keys are generated, then closes and reopens the vault from the
  /// recent vaults list to confirm session state is restored.
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
      /* Arrange: launch the app shell */
      await tester.pumpWidget(const MainApp());
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

      expect(
        await File(p.join(vaultPath, 'pages', 'welcome.md')).exists(),
        isTrue,
      );

      await expectPageFileValid(vaultPath, 'pages/welcome.md');

      // Assert: vault recorded in recent vaults settings
      final recentRaw = await settings.getString('noetec.recent_vaults');
      expect(recentRaw, isNotNull);
      final recentVaults = json.decode(recentRaw!) as List<dynamic>;
      expect(
        recentVaults.any(
          (item) => (item as Map<String, dynamic>)['rootPath'] == vaultPath,
        ),
        isTrue,
      );

      // Assert: session state tracks welcome page as open and active
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      expect(
        await Directory(p.join(vaultPath, '.sync', 'pages')).exists(),
        isTrue,
      );

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
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Assert: pages were restored in PageSystem
      expect(pageSystem.openPages.length, equals(1));
      final restoredPaths = pageSystem.openPages.values
          .map((e) => e.relativePath)
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
}
