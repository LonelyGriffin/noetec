import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_assertions.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// E2E Scenario: User types text into the welcome page, saves, then closes
  /// and reopens the vault. After reopening, verify that the edited content is
  /// restored in memory and that the on-disk file hash matches the saved hash.
  testWidgets('Edited content persists after closing and reopening vault', (
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
      expect(
        findTabUnsavedIndicator('welcome'),
        findsOneWidget,
        reason: 'Tab should show unsaved indicator before Ctrl+S',
      );

      // Act: save with Ctrl+S
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Assert: unsaved indicator disappears after save
      expect(
        findTabUnsavedIndicator('welcome'),
        findsNothing,
        reason: 'Tab should not show unsaved indicator after Ctrl+S',
      );

      // Arrange: capture hash after save
      final hashAfterSave = await readContentHash(
        vaultPath,
        'pages/welcome.md',
      );

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
      final welcomeContent = await File(
        p.join(vaultPath, 'pages', 'welcome.md'),
      ).readAsString();
      expect(welcomeContent, contains('hello'));

      // Act: reopen vault from recent vaults
      await tester.tap(findRecentVaultEntry('PersistVault'));
      await tester.pumpAndSettle();

      // Assert: pages restored in memory
      expect(pageSystem.openPages, isNotEmpty);
      final restoredBlock = pageSystem
          .getActivePage()!
          .rootBlocks
          .whereType<TextBlockEntity>()
          .first;
      expect(restoredBlock.computeAllSegmentsText(), contains('hello'));

      // Assert: file hash unchanged after reopen (content was saved)
      final hashAfterReopen = await readContentHash(
        vaultPath,
        'pages/welcome.md',
      );
      expect(hashAfterReopen, equals(hashAfterSave));

      // Assert: no unsaved indicator since content was saved before closing
      expect(
        findTabUnsavedIndicator('welcome'),
        findsNothing,
        reason: 'Tab should not show unsaved indicator (content was saved)',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
