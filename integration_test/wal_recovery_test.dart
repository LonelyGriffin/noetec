// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

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

  /// Scenario A1: User types into welcome page WITHOUT saving, closes and reopens vault.
  /// WAL should auto-recover the edits and display unsaved indicator.
  testWidgets('A1: Unsaved edits in WAL recover when page reopened', (
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

      await tester.enterText(findVaultNameField(), 'WalRecoveryVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'WalRecoveryVault');

      // Act: focus editor and type "unsaved text"
      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);

      // Allow auto-save / crash-recovery debounce to flush
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: text is in memory
      final pageSystem = GetIt.instance<PageSystem>();
      final textBlock = pageSystem
          .getActivePage()!
          .rootBlocks
          .whereType<TextBlockEntity>()
          .first;
      expect(textBlock.computeAllSegmentsText(), contains('unsaved'));

      // Assert: WAL contains the edit
      await expectCrashRecoveryLogContains(
        vaultPath,
        'pages/welcome.md',
        actionType: 'insert_text',
        text: 'unsaved',
      );

      // Assert: unsaved indicator is shown
      expect(
        findTabUnsavedIndicator('welcome'),
        findsOneWidget,
        reason: 'Tab should show unsaved indicator before close',
      );

      // Act: close vault WITHOUT saving (Ctrl+S not used)
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findOpenAnotherVaultButton());
      await tester.tap(findOpenAnotherVaultButton());
      await tester.pumpAndSettle();

      // Assert: in-memory state cleared
      expect(pageSystem.openPages, isEmpty);

      // Assert: on-disk file does NOT contain "unsaved" (not saved)
      final welcomeContent = await File(
        p.join(vaultPath, 'pages', 'welcome.md'),
      ).readAsString();
      expect(welcomeContent, isNot(contains('unsaved')));

      // Assert: WAL still exists (unsaved edits)
      await expectWalExists(vaultPath, 'pages/welcome.md');

      // Act: reopen vault from recent vaults
      await tester.tap(findRecentVaultEntry('WalRecoveryVault'));
      await tester.pumpAndSettle();

      // Assert: welcome page is open
      expect(findTabWithTitle('welcome'), findsOneWidget);

      // Assert: text recovered from WAL in memory
      final restoredBlock = pageSystem
          .getActivePage()!
          .rootBlocks
          .whereType<TextBlockEntity>()
          .first;
      expect(restoredBlock.computeAllSegmentsText(), contains('unsaved'));

      // Assert: unsaved indicator displayed (recovered state is considered unsaved)
      expect(
        findTabUnsavedIndicator('welcome'),
        findsOneWidget,
        reason: 'Tab should show unsaved indicator after WAL recovery',
      );

      // Assert: WAL still exists (state not yet saved to disk)
      await expectWalExists(vaultPath, 'pages/welcome.md');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });

  /// Scenario A2: Multiple pages without saving. Both should be recovered with WAL.
  testWidgets(
    'A2: Multiple unsaved pages recover independently with correct indicators',
    (tester) async {
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

        await tester.enterText(findVaultNameField(), 'MultiPageVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'MultiPageVault');
        final pageSystem = GetIt.instance<PageSystem>();

        // Act: create extra.md
        await tester.tap(findPagesPanelButton());
        await tester.pumpAndSettle();

        await tester.tap(findNewPageButton());
        await tester.pumpAndSettle();

        await tester.enterText(findPageRenameField(), 'extra');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Act: open extra.md and edit it
        await tester.tap(findPagesPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findPageInPanel('extra.md'));
        await tester.tap(findPageInPanel('extra.md'));
        await tester.pumpAndSettle();

        // Act: type "extra text" in extra.md
        await tester.tap(findEditorBlock());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

        // Allow debounce
        await tester.pump(const Duration(milliseconds: 500));

        // Act: switch to welcome and edit it too
        await tester.tap(findTabWithTitle('welcome'));
        await tester.pumpAndSettle();

        await tester.tap(findEditorBlock());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);

        // Allow debounce
        await tester.pump(const Duration(milliseconds: 500));

        // Assert: both tabs show unsaved
        expect(findTabUnsavedIndicator('extra'), findsOneWidget);
        expect(findTabUnsavedIndicator('welcome'), findsOneWidget);

        // Assert: WALs for both pages
        await expectCrashRecoveryLogContains(
          vaultPath,
          'pages/extra.md',
          actionType: 'insert_text',
          text: 'extra',
        );
        await expectCrashRecoveryLogContains(
          vaultPath,
          'pages/welcome.md',
          actionType: 'insert_text',
          text: 'welcome',
        );

        // Act: close vault without saving
        await tester.tap(findSettingsPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findOpenAnotherVaultButton());
        await tester.tap(findOpenAnotherVaultButton());
        await tester.pumpAndSettle();

        expect(pageSystem.openPages, isEmpty);

        // Act: reopen vault
        await tester.tap(findRecentVaultEntry('MultiPageVault'));
        await tester.pumpAndSettle();

        // Assert: both pages are open (were open before close)
        expect(pageSystem.openPages, isNotEmpty);
        expect(findTabWithTitle('welcome'), findsOneWidget);
        expect(findTabWithTitle('extra'), findsOneWidget);

        // Assert: both show unsaved indicators
        expect(findTabUnsavedIndicator('welcome'), findsOneWidget);
        expect(findTabUnsavedIndicator('extra'), findsOneWidget);

        // Assert: both contents recovered
        final welcomePage = pageSystem.openPages.values
            .where((p) => p.title == 'welcome')
            .first;
        final welcomeText = welcomePage.rootBlocks
            .whereType<TextBlockEntity>()
            .first
            .computeAllSegmentsText();
        expect(welcomeText, contains('welcome'));

        final extraPage = pageSystem.openPages.values
            .where((p) => p.title == 'extra')
            .first;
        final extraText = extraPage.rootBlocks
            .whereType<TextBlockEntity>()
            .first
            .computeAllSegmentsText();
        expect(extraText, contains('extra'));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    },
  );

  /// Scenario A3: One page saved (no WAL), another unsaved (has WAL).
  /// Indicators should differ between them.
  testWidgets('A3: Mixed saved and unsaved pages recover with isolated WALs', (
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

      await tester.enterText(findVaultNameField(), 'MixedVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'MixedVault');
      final pageSystem = GetIt.instance<PageSystem>();

      // Act: create extra.md
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.tap(findNewPageButton());
      await tester.pumpAndSettle();

      await tester.enterText(findPageRenameField(), 'extra');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Act: open extra.md and edit + save it
      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findPageInPanel('extra.md'));
      await tester.tap(findPageInPanel('extra.md'));
      await tester.pumpAndSettle();

      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);

      await tester.pump(const Duration(milliseconds: 500));

      // Act: save extra.md with Ctrl+S
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Assert: extra is saved (no unsaved indicator)
      expect(findTabUnsavedIndicator('extra'), findsNothing);

      // Act: switch to welcome and edit WITHOUT saving
      await tester.tap(findTabWithTitle('welcome'));
      await tester.pumpAndSettle();

      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);

      await tester.pump(const Duration(milliseconds: 500));

      // Assert: welcome unsaved, extra saved
      expect(findTabUnsavedIndicator('welcome'), findsOneWidget);
      expect(findTabUnsavedIndicator('extra'), findsNothing);

      // Act: close vault without saving welcome
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findOpenAnotherVaultButton());
      await tester.tap(findOpenAnotherVaultButton());
      await tester.pumpAndSettle();

      // Assert: extra.md has NO WAL (was saved)
      await expectCrashRecoveryLogAbsent(vaultPath, 'pages/extra.md');

      // Assert: welcome.md HAS WAL (was not saved)
      await expectWalExists(vaultPath, 'pages/welcome.md');

      // Act: reopen vault
      await tester.tap(findRecentVaultEntry('MixedVault'));
      await tester.pumpAndSettle();

      // Assert: extra tab shows close button (no unsaved, from disk)
      expect(
        findTabCloseButton('extra'),
        findsOneWidget,
        reason: 'Extra should show close button, not unsaved indicator',
      );

      // Assert: welcome tab shows unsaved indicator (from WAL)
      expect(
        findTabUnsavedIndicator('welcome'),
        findsOneWidget,
        reason: 'Welcome should show unsaved indicator (recovered from WAL)',
      );

      // Assert: welcome content recovered from WAL
      final welcomePage = pageSystem.openPages.values
          .where((p) => p.title == 'welcome')
          .first;
      final welcomeText = welcomePage.rootBlocks
          .whereType<TextBlockEntity>()
          .first
          .computeAllSegmentsText();
      expect(welcomeText, contains('unsaved'));

      // Assert: extra content is from disk (original, not WAL)
      final extraPage = pageSystem.openPages.values
          .where((p) => p.title == 'extra')
          .first;
      final extraText = extraPage.rootBlocks
          .whereType<TextBlockEntity>()
          .first
          .computeAllSegmentsText();
      expect(extraText, contains('saved'));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });

  /// Scenario C1: Recover from WAL → add more edits → save to disk.
  testWidgets('C1: Edit after WAL recovery persists correctly', (tester) async {
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

      await tester.enterText(findVaultNameField(), 'C1Vault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      final vaultPath = p.join(parentDir.rootPath, 'C1Vault');

      // Act: edit and close without saving
      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);

      await tester.pump(const Duration(milliseconds: 500));

      final pageSystem = GetIt.instance<PageSystem>();

      // Act: close vault
      await tester.tap(findSettingsPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findOpenAnotherVaultButton());
      await tester.tap(findOpenAnotherVaultButton());
      await tester.pumpAndSettle();

      // Act: reopen vault (WAL recovery)
      await tester.tap(findRecentVaultEntry('C1Vault'));
      await tester.pumpAndSettle();

      // Assert: content recovered
      final textBlock = pageSystem
          .getActivePage()!
          .rootBlocks
          .whereType<TextBlockEntity>()
          .first;
      expect(textBlock.computeAllSegmentsText(), contains('first'));

      // Act: add more text after recovery
      await tester.tap(findEditorBlock());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);

      await tester.pump(const Duration(milliseconds: 500));

      // Act: save with Ctrl+S
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Assert: file on disk contains both parts
      final welcomeContent = await File(
        p.join(vaultPath, 'pages', 'welcome.md'),
      ).readAsString();
      expect(welcomeContent, contains('first'));
      expect(welcomeContent, contains('second'));

      // Assert: WAL cleared after save
      await expectCrashRecoveryLogAbsent(vaultPath, 'pages/welcome.md');

      // Assert: unsaved indicator gone
      expect(findTabUnsavedIndicator('welcome'), findsNothing);

      // Assert: op log records save
      await expectOpLogContains(
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
