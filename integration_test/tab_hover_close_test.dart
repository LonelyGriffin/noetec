import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Dirty tab shows circle, hover reveals close icon, tap closes tab',
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
        await tester.pumpWidget(const MainApp());
        await tester.pumpAndSettle();

        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'HoverVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        await tester.tap(findEditorBlock());
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
        await tester.pump(const Duration(milliseconds: 500));

        expect(findTabUnsavedIndicator('welcome'), findsOneWidget);
        expect(findTabCloseButton('welcome'), findsNothing);

        final gesture1 = await hoverOver(
          tester,
          findTabUnsavedIndicator('welcome'),
        );

        expect(findTabUnsavedIndicator('welcome'), findsNothing);
        expect(findTabCloseButton('welcome'), findsOneWidget);

        await hoverAway(tester, gesture1);

        expect(findTabUnsavedIndicator('welcome'), findsOneWidget);
        expect(findTabCloseButton('welcome'), findsNothing);

        final gesture2 = await hoverOver(
          tester,
          findTabUnsavedIndicator('welcome'),
        );
        await tester.tap(findTabCloseButton('welcome'));
        await tester.pumpAndSettle();
        await hoverAway(tester, gesture2);

        expect(findTabWithTitle('welcome'), findsNothing);
        expect(find.text('Open a page to start editing'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    },
  );

  testWidgets('Closing non-active tab removes it from tab bar', (tester) async {
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

      await tester.tap(findCreateVaultButton());
      await tester.pumpAndSettle();

      await tester.enterText(findVaultNameField(), 'MultiTabVault');
      await tester.tap(findDialogCreateButton());
      await tester.pumpAndSettle();

      expect(findTabWithTitle('welcome'), findsOneWidget);

      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.tap(findNewPageButton());
      await tester.pumpAndSettle();

      await tester.enterText(findPageRenameField(), 'second');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(findPagesPanelButton());
      await tester.pumpAndSettle();

      await tester.ensureVisible(findPageInPanel('second.md'));
      await tester.tap(findPageInPanel('second.md'));
      await tester.pumpAndSettle();

      expect(findTabWithTitle('welcome'), findsOneWidget);
      expect(findTabWithTitle('second'), findsOneWidget);

      await tester.tap(findTabCloseButton('welcome'));
      await tester.pumpAndSettle();

      expect(findTabWithTitle('welcome'), findsNothing);
      expect(findTabWithTitle('second'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
