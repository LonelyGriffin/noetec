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

  /// E2E Scenario: User types text into the welcome page, verifies the crash
  /// recovery log captures the edit, then saves with Ctrl+S. After save, the
  /// recovery log is cleared, the on-disk file is updated, and the op log
  /// records the save operation.
  testWidgets(
    'User types text into welcome page and saves — files updated correctly',
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

        await tester.enterText(findVaultNameField(), 'EditVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'EditVault');

        // Arrange: capture hash before editing
        final oldHash = await readContentHash(vaultPath, 'pages/welcome.md');

        // Act: focus editor and type "hello"
        await tester.tap(findEditorBlock());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);

        // Assert: in-memory text block contains typed text
        final pageSystem = GetIt.instance<PageSystem>();
        final textBlock = pageSystem
            .getActivePage()!
            .rootBlocks
            .whereType<TextBlockEntity>()
            .first;
        expect(textBlock.computeAllSegmentsText(), contains('hello'));

        // Allow auto-save / crash-recovery debounce to flush
        await tester.pump(const Duration(milliseconds: 500));

        // Assert: crash recovery log has the edit entry
        await expectCrashRecoveryLogContains(
          vaultPath,
          'pages/welcome.md',
          actionType: 'insert_text',
          text: 'hello',
        );

        // Act: save with Ctrl+S
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        // Assert: crash recovery log cleared after save
        await expectCrashRecoveryLogAbsent(vaultPath, 'pages/welcome.md');

        // Assert: file content hash changed
        await expectPageFileContentHashChanged(
          vaultPath,
          'pages/welcome.md',
          oldHash,
        );

        // Assert: saved file contains the typed text
        await expectPageFileValid(
          vaultPath,
          'pages/welcome.md',
          containsText: 'hello',
        );

        // Assert: op log records the save
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
    },
  );
}
