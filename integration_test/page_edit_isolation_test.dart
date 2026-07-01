import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_assertions.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// E2E Scenario: User creates a vault with two pages, then types into only
  /// one. After saving, verify that the edited page file is updated, the
  /// crash-recovery log only records edits for that page, and the other page's
  /// file content and op log remain untouched.
  testWidgets('Edits on one page do not affect other page files', (
    tester,
  ) async {
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

      await tester.enterText(findVaultNameField(), 'IsoVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'IsoVault');

      // Act: create extra.md via Pages panel
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.tap(findNewPageButton());
      await tester.pumpAndSettle();

      await tester.enterText(findPageRenameField(), 'extra');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Act: open extra.md for editing
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      // Arrange: capture welcome page hash before any edits
      final welcomeHash = await readContentHash(vaultPath, 'pages/welcome.md');

      // Act: focus editor and type "my notes"
      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);

      // Allow crash-recovery debounce to flush
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: extra.md tab shows unsaved indicator, welcome.md shows close button
      expect(
        findTabUnsavedIndicator('extra'),
        findsOneWidget,
        reason: 'Extra tab should show unsaved indicator',
      );
      expect(
        findTabCloseButton('welcome'),
        findsOneWidget,
        reason: 'Welcome tab should show close button (not unsaved)',
      );

      // Assert: crash recovery log records edit only for extra.md
      await expectCrashRecoveryLogContains(
        vaultPath,
        'pages/extra.md',
        actionType: 'insert_text',
        text: 'my notes',
      );
      await expectCrashRecoveryLogAbsent(vaultPath, 'pages/welcome.md');

      // Act: save with Ctrl+S
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Assert: extra.md unsaved indicator disappears after save
      expect(
        findTabUnsavedIndicator('extra'),
        findsNothing,
        reason: 'Extra tab should not show unsaved indicator after Ctrl+S',
      );

      // Assert: recovery log cleared, extra.md file updated
      await expectCrashRecoveryLogAbsent(vaultPath, 'pages/extra.md');
      await expectPageFileValid(
        vaultPath,
        'pages/extra.md',
        containsText: 'my notes',
      );

      // Assert: welcome page file hash has not changed
      final welcomeHashAfter = await readContentHash(
        vaultPath,
        'pages/welcome.md',
      );
      expect(welcomeHashAfter, equals(welcomeHash));

      // Assert: op log only written for extra.md, not welcome.md
      await expectOpLogExists(vaultPath, 'pages/extra.md');
      // welcome.md has file_create from vault init, but no edit/save entries
      await expectOpLogDoesNotContain(
        vaultPath,
        'pages/welcome.md',
        entryType: 'edit',
      );
      await expectOpLogDoesNotContain(
        vaultPath,
        'pages/welcome.md',
        entryType: 'save',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
