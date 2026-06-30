import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/session_assertions.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// E2E Scenario: User creates a vault, opens multiple page tabs, closes tabs
  /// one by one, and verifies session state stays in sync. Then reopens a
  /// previously closed page to confirm tab management and session persistence.
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
      /* Arrange: launch the app shell */
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();

      // Act: create vault
      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'TabVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'TabVault');

      // Assert: welcome tab is open in editor
      expect(findTabWithTitle('welcome'), findsOneWidget);

      // Assert: initial session has only welcome.md
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Act: create extra.md via Pages panel
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.tap(findNewPageButton());
      await tester.pumpAndSettle();

      await tester.enterText(findPageRenameField(), 'extra');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Assert: extra.md file created on disk
      expect(
        await File(p.join(vaultPath, 'pages', 'extra.md')).exists(),
        isTrue,
      );

      // Act: open extra.md from Pages panel
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      // Assert: session tracks both pages, extra.md is active
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md', 'pages/extra.md'],
        expectedActivePagePath: 'pages/extra.md',
      );

      // Act: close extra.md tab via UI
      await tester.tap(findTabCloseButton('extra'));
      await tester.pumpAndSettle();

      // Assert: extra tab removed, welcome still present
      expect(findTabWithTitle('extra'), findsNothing);
      expect(findTabWithTitle('welcome'), findsOneWidget);

      // Assert: session updated — only welcome.md remains
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: ['pages/welcome.md'],
        expectedActivePagePath: 'pages/welcome.md',
      );

      // Act: close welcome.md tab via UI
      await tester.tap(findTabCloseButton('welcome'));
      await tester.pumpAndSettle();

      // Assert: editor shows empty state message
      expect(find.text('Open a page to start editing'), findsOneWidget);

      // Assert: session is empty
      await expectSessionJsonValid(
        vaultPath,
        expectedOpenPagePaths: [],
        expectedActivePagePath: null,
      );

      // Act: reopen extra.md via Pages panel (panel is already open)
      expect(findPageInPanel('extra.md'), findsOneWidget);
      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      // Assert: tab for extra is present
      expect(findTabWithTitle('extra'), findsOneWidget);

      // Assert: session updated with extra.md as sole open page
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
