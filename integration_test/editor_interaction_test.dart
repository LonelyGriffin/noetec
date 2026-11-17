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
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/service/page_file_name_sanitizer.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/pump_test_app.dart';
import 'helpers/session_assertions.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_assertions.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

Future<List<String>> listPages(String vaultPath) async {
  final pagesDir = Directory(p.join(vaultPath, 'pages'));
  if (!await pagesDir.exists()) return [];
  return (await pagesDir.list(recursive: true).toList()).whereType<File>().where((f) => f.path.endsWith('.md')).map((f) => p.relative(f.path, from: vaultPath)).toList()..sort();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Editing and saving', () {
    /// E2E Scenario: User types text into the welcome page, verifies the crash
    /// recovery log captures the edit, then saves with Ctrl+S. After save, the
    /// recovery log is cleared, the on-disk file is updated, and the op log
    /// records the save operation.
    testWidgets('User types text into welcome page and saves — files updated correctly', (tester) async {
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
        final textBlock = pageSystem.getActivePage()!.rootBlocks.whereType<TextBlockEntity>().first;
        expect(textBlock.computeAllSegmentsText(), contains('hello'));

        // Allow auto-save / crash-recovery debounce to flush
        await tester.pump(const Duration(milliseconds: 500));

        // Assert: tab shows unsaved indicator (circle icon) after editing
        expect(findTabUnsavedIndicator('welcome'), findsOneWidget, reason: 'Tab should show unsaved indicator before Ctrl+S');

        // Assert: crash recovery log has the edit entry
        await expectCrashRecoveryLogContains(vaultPath, 'pages/welcome.md', actionType: 'insert_text', text: 'hello');

        // Act: save with Ctrl+S
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        // Assert: unsaved indicator (circle) disappears after save
        expect(findTabUnsavedIndicator('welcome'), findsNothing, reason: 'Tab should not show unsaved indicator after Ctrl+S');

        // Assert: crash recovery log cleared after save
        await expectCrashRecoveryLogAbsent(vaultPath, 'pages/welcome.md');

        // Assert: file content hash changed
        await expectPageFileContentHashChanged(vaultPath, 'pages/welcome.md', oldHash);

        // Assert: saved file contains the typed text
        await expectPageFileValid(vaultPath, 'pages/welcome.md', containsText: 'hello');

        // Assert: op log records the save
        await expectOpLogContains(vaultPath, 'pages/welcome.md', entryType: 'save');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    /// E2E Scenario: User creates a vault with two pages, then types into only
    /// one. After saving, verify that the edited page file is updated, the
    /// crash-recovery log only records edits for that page, and the other page's
    /// file content and op log remain untouched.
    testWidgets('Edits on one page do not affect other page files', (tester) async {
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
        expect(findTabUnsavedIndicator('extra'), findsOneWidget, reason: 'Extra tab should show unsaved indicator');
        expect(findTabCloseButton('welcome'), findsOneWidget, reason: 'Welcome tab should show close button (not unsaved)');

        // Assert: crash recovery log records edit only for extra.md
        await expectCrashRecoveryLogContains(vaultPath, 'pages/extra.md', actionType: 'insert_text', text: 'my notes');
        await expectCrashRecoveryLogAbsent(vaultPath, 'pages/welcome.md');

        // Act: save with Ctrl+S
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        // Assert: extra.md unsaved indicator disappears after save
        expect(findTabUnsavedIndicator('extra'), findsNothing, reason: 'Extra tab should not show unsaved indicator after Ctrl+S');

        // Assert: recovery log cleared, extra.md file updated
        await expectCrashRecoveryLogAbsent(vaultPath, 'pages/extra.md');
        await expectPageFileValid(vaultPath, 'pages/extra.md', containsText: 'my notes');

        // Assert: welcome page file hash has not changed
        final welcomeHashAfter = await readContentHash(vaultPath, 'pages/welcome.md');
        expect(welcomeHashAfter, equals(welcomeHash));

        // Assert: op log only written for extra.md, not welcome.md
        await expectOpLogExists(vaultPath, 'pages/extra.md');
        // welcome.md has file_create from vault init, but no edit/save entries
        await expectOpLogDoesNotContain(vaultPath, 'pages/welcome.md', entryType: 'edit');
        await expectOpLogDoesNotContain(vaultPath, 'pages/welcome.md', entryType: 'save');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });
  });

  group('Page tabs', () {
    /// E2E Scenario: User creates a vault, opens multiple page tabs, closes tabs
    /// one by one, and verifies session state stays in sync. Then reopens a
    /// previously closed page to confirm tab management and session persistence.
    testWidgets('Page tab management and session persistence', (tester) async {
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

        await tester.enterText(findVaultNameField(), 'TabVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'TabVault');

        // Assert: welcome tab is open in editor
        expect(findTabWithTitle('welcome'), findsOneWidget);

        // Assert: initial session has only welcome.md
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        // Act: create extra.md via Pages panel
        await tester.tap(findPagesPanelButton());
        await tester.pumpAndSettle();

        await tester.tap(findNewPageButton());
        await tester.pumpAndSettle();

        await tester.enterText(findPageRenameField(), 'extra');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Assert: extra.md file created on disk
        expect(await File(p.join(vaultPath, 'pages', 'extra.md')).exists(), isTrue);

        // Act: open extra.md from Pages panel
        await tester.tap(findPagesPanelButton());
        await tester.pumpAndSettle();

        await tester.ensureVisible(findPageInPanel('extra.md'));
        await tester.tap(findPageInPanel('extra.md'));
        await tester.pumpAndSettle();

        // Assert: session tracks both pages, extra.md is active
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/welcome.md', 'pages/extra.md'], expectedActivePagePath: 'pages/extra.md');

        // Act: close extra.md tab via UI
        await tester.tap(findTabCloseButton('extra'));
        await tester.pumpAndSettle();

        // Assert: extra tab removed, welcome still present
        expect(findTabWithTitle('extra'), findsNothing);
        expect(findTabWithTitle('welcome'), findsOneWidget);

        // Assert: session updated — only welcome.md remains
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/welcome.md'], expectedActivePagePath: 'pages/welcome.md');

        // Act: close welcome.md tab via UI
        await tester.tap(findTabCloseButton('welcome'));
        await tester.pumpAndSettle();

        // Assert: editor shows empty state message
        expect(find.text('Open a page to start editing'), findsOneWidget);

        // Assert: session is empty
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: [], expectedActivePagePath: null);

        // Act: reopen extra.md via Pages panel (panel is already open)
        expect(findPageInPanel('extra.md'), findsOneWidget);
        await tester.ensureVisible(findPageInPanel('extra.md'));
        await tester.tap(findPageInPanel('extra.md'));
        await tester.pumpAndSettle();

        // Assert: tab for extra is present
        expect(findTabWithTitle('extra'), findsOneWidget);

        // Assert: session updated with extra.md as sole open page
        await expectSessionJsonValid(vaultPath, expectedOpenPagePaths: ['pages/extra.md'], expectedActivePagePath: 'pages/extra.md');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    testWidgets('Dirty tab shows circle, hover reveals close icon, tap closes tab', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        await pumpTestApp(tester);
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

        final gesture1 = await hoverOver(tester, findTabUnsavedIndicator('welcome'));

        expect(findTabUnsavedIndicator('welcome'), findsNothing);
        expect(findTabCloseButton('welcome'), findsOneWidget);

        await hoverAway(tester, gesture1);

        expect(findTabUnsavedIndicator('welcome'), findsOneWidget);
        expect(findTabCloseButton('welcome'), findsNothing);

        final gesture2 = await hoverOver(tester, findTabUnsavedIndicator('welcome'));
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
    });

    testWidgets('Closing non-active tab removes it from tab bar', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        await pumpTestApp(tester);
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
  });

  group('Page rename', () {
    /// E2E Scenario: user renames pages. Names with path separators or
    /// illegal characters are flattened on disk (no nested paths, no
    /// traversal); names that sanitize to nothing, and names colliding with
    /// an existing page, are rejected with the original file untouched.
    testWidgets('Page rename sanitization and rejection', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        /* Arrange: launch app shell and create a vault */
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'SanitizeVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'SanitizeVault');
        expect(findTabWithTitle('welcome'), findsOneWidget);

        // Create a fresh page (auto-enters rename) and commit the given name
        // by moving focus away from the rename field.
        Future<void> commitRenameInPanel(String name) async {
          await tester.tap(findNewPageButton());
          await tester.pumpAndSettle();
          await tester.enterText(findPageRenameField(), name);
          // Commit via focus loss: tap the welcome row (plain selection).
          await tester.tap(find.text('welcome.md'));
          await tester.pumpAndSettle();
        }

        /* Act 1: rename to a name with a path separator */
        await commitRenameInPanel('a/b');

        // Assert: file exists under the sanitized name, no nested directory
        expect(await File(p.join(vaultPath, 'pages', 'a-b.md')).exists(), isTrue, reason: 'separator in name must be flattened to a dash');
        expect(await Directory(p.join(vaultPath, 'pages', 'a')).exists(), isFalse, reason: 'no nested directory may be created');
        expect(findPageInPanel('a-b.md'), findsOneWidget);

        // Act 2: rename to a name with backslash, colon and wildcards
        await commitRenameInPanel(r'a\b:c*');

        // Assert: all invalid characters become one collapsed dash
        expect(await File(p.join(vaultPath, 'pages', 'a-b-c.md')).exists(), isTrue, reason: 'invalid chars \\ : * must become a single dash');
        expect(findPageInPanel('a-b-c.md'), findsOneWidget);

        // Act 3: reject a name that sanitizes to empty (///)
        await tester.runAsync(() async {
          final vaultFileService = GetIt.I<VaultFileService>();
          final relative = await vaultFileService.createPage(vaultPath);
          Object? error;
          try {
            await vaultFileService.renamePage(vaultPath, relative, '///');
          } catch (e) {
            error = e;
          }

          expect(error, isA<PageNameInvalidException>());

          // The original page must be intact: not renamed, not deleted
          expect(await File(p.join(vaultPath, relative)).exists(), isTrue);
          // No bogus file may have appeared
          expect(await listPages(vaultPath), isNot(contains(p.join('pages', '.md'))));
        });

        // Act 4: reject a rename that collides with an existing page
        await tester.runAsync(() async {
          final vaultFileService = GetIt.I<VaultFileService>();
          final relative = await vaultFileService.createPage(vaultPath);
          Object? error;
          try {
            await vaultFileService.renamePage(vaultPath, relative, 'welcome');
          } catch (e) {
            error = e;
          }

          expect(error, isA<PageNameConflictException>());

          // Neither page may have been touched
          expect(await File(p.join(vaultPath, relative)).exists(), isTrue);
          final pages = await listPages(vaultPath);
          expect(pages.where((e) => e.endsWith('welcome.md')), hasLength(1));
        });

        // Act 5: a plain valid rename still works (regression guard)
        await commitRenameInPanel('final');

        // Assert: source renamed away, panel updated
        expect(await File(p.join(vaultPath, 'pages', 'final.md')).exists(), isTrue, reason: 'plain rename must still work');
        expect(findPageInPanel('final.md'), findsOneWidget);

        // Assert: all pages survived, session file intact
        final pages = await listPages(vaultPath);
        expect(pages, containsAll([p.join('pages', 'a-b-c.md'), p.join('pages', 'a-b.md'), p.join('pages', 'final.md'), p.join('pages', 'welcome.md')]));
        expect(await File(p.join(vaultPath, '.noetec', 'session.json')).exists(), isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    /// E2E Scenario: the exact NOET-17 bug. Committing a rename by pressing
    /// Enter previously fired `onSubmitted` and, after the `finally`-driven
    /// rebuild dropped focus, the focus-loss handler — so `_commitRename` ran
    /// twice. The second `renamePage` call found the target path already
    /// present and threw `PageNameConflictException`, which surfaced as an
    /// unhandled error. With the `RenameController` phase guard (`confirm`
    /// transitions editing -> committing before calling renamePage, so the
    /// second call is a no-op), Enter commits exactly
    /// once: file renamed, old path gone, no error surfaced, field cleared.
    ///
    /// Soundness of "exactly once": a second commit would throw (target
    /// exists) -> takeException() non-null; zero commits -> file not renamed
    /// -> contains('entered.md') fails. Only exactly-once satisfies all.
    testWidgets('Enter commit renames exactly once (no double-commit error)', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'EnterVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'EnterVault');

        // Create a fresh page; the panel auto-enters rename with the
        // suggested name selected.
        await tester.tap(findNewPageButton());
        await tester.pumpAndSettle();
        expect(findPageRenameField(), findsOneWidget);

        // Type the new name, then commit with Enter (done action) — NOT by
        // tapping away, so the onSubmitted path is exercised directly.
        await tester.enterText(findPageRenameField(), 'entered');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // AC: no error surfaced (the second commit used to throw
        // PageNameConflictException / PathNotFoundException).
        expect(tester.takeException(), isNull, reason: 'Enter commit must not surface a double-commit error');

        // AC: renamed exactly once — new path present, no duplicate, and the
        // panel now shows the page name (rename field cleared, commit done).
        final pages = await listPages(vaultPath);
        expect(pages, contains(p.join('pages', 'entered.md')));
        expect(pages.where((e) => e.contains('untitled')).isEmpty, isTrue, reason: 'the suggested-name placeholder must be gone, not duplicated');
        expect(findPageInPanel('entered.md'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });

    /// AC: Escape still cancels without committing. The `RenameController`
    /// commit-once invariant only guards `confirm`; `cancel` never reaches it,
    /// so the guard cannot affect Escape — but we verify it end-to-end: type a
    /// name, press Escape, and confirm the file was NOT renamed and no error
    /// surfaced (the created placeholder page survives).
    testWidgets('Escape cancels rename without committing', (tester) async {
      final fileSystem = TestFileSystemService();
      final settings = InMemorySettingsService();
      final secureKeyStore = InMemorySecureKeyStore();
      final parentDir = await VaultFolderFixture.createEmpty();
      fileSystem.nextPickPath = parentDir.rootPath;

      await configureDI(fileSystem: fileSystem, settings: settings, secureKeyStore: secureKeyStore);

      try {
        await pumpTestApp(tester);
        await tester.pumpAndSettle();

        await tester.tap(findCreateVaultButton());
        await tester.pumpAndSettle();

        await tester.enterText(findVaultNameField(), 'EscapeVault');
        await tester.tap(findDialogCreateButton());
        await tester.pumpAndSettle();

        final vaultPath = p.join(parentDir.rootPath, 'EscapeVault');

        // Create a fresh page; the panel auto-enters rename.
        await tester.tap(findNewPageButton());
        await tester.pumpAndSettle();
        expect(findPageRenameField(), findsOneWidget);

        // Type a name, then press Escape to cancel.
        await tester.enterText(findPageRenameField(), 'canceled');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        // AC: no error surfaced.
        expect(tester.takeException(), isNull, reason: 'Escape cancel must not surface an error');

        // AC: NOT committed — typed name absent, placeholder (untitled*) remains.
        final pages = await listPages(vaultPath);
        expect(pages.where((e) => e.contains('canceled')).isEmpty, isTrue, reason: 'Escape must cancel — the typed name must not be written');
        expect(pages.where((e) => e.contains('untitled')).isNotEmpty, isTrue, reason: 'the created placeholder page must survive the cancel');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.instance.reset();
        await parentDir.dispose();
      }
    });
  });
}
