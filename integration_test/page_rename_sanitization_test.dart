import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/service/page_file_name_sanitizer.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:path/path.dart' as p;

import 'helpers/in_memory_secure_key_store.dart';
import 'helpers/in_memory_settings_service.dart';
import 'helpers/test_file_system_service.dart';
import 'helpers/vault_folder_fixture.dart';
import 'helpers/widget_finders.dart';

Future<List<String>> listPages(String vaultPath) async {
  final pagesDir = Directory(p.join(vaultPath, 'pages'));
  if (!await pagesDir.exists()) return [];
  return (await pagesDir.list(recursive: true).toList())
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .map((f) => p.relative(f.path, from: vaultPath))
      .toList()
    ..sort();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

    await configureDI(
      fileSystem: fileSystem,
      settings: settings,
      secureKeyStore: secureKeyStore,
    );

    try {
      /* Arrange: launch app shell and create a vault */
      await tester.pumpWidget(const MainApp());
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
      expect(
        await File(p.join(vaultPath, 'pages', 'a-b.md')).exists(),
        isTrue,
        reason: 'separator in name must be flattened to a dash',
      );
      expect(
        await Directory(p.join(vaultPath, 'pages', 'a')).exists(),
        isFalse,
        reason: 'no nested directory may be created',
      );
      expect(findPageInPanel('a-b.md'), findsOneWidget);

      // Act 2: rename to a name with backslash, colon and wildcards
      await commitRenameInPanel(r'a\b:c*');

      // Assert: all invalid characters become one collapsed dash
      expect(
        await File(p.join(vaultPath, 'pages', 'a-b-c.md')).exists(),
        isTrue,
        reason: 'invalid chars \\ : * must become a single dash',
      );
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
      expect(
        await File(p.join(vaultPath, 'pages', 'final.md')).exists(),
        isTrue,
        reason: 'plain rename must still work',
      );
      expect(findPageInPanel('final.md'), findsOneWidget);

      // Assert: all pages survived, session file intact
      final pages = await listPages(vaultPath);
      expect(
        pages,
        containsAll([
          p.join('pages', 'a-b-c.md'),
          p.join('pages', 'a-b.md'),
          p.join('pages', 'final.md'),
          p.join('pages', 'welcome.md'),
        ]),
      );
      expect(
        await File(p.join(vaultPath, '.noetec', 'session.json')).exists(),
        isTrue,
      );
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
  testWidgets('Enter commit renames exactly once (no double-commit error)',
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
      expect(
        tester.takeException(),
        isNull,
        reason: 'Enter commit must not surface a double-commit error',
      );

      // AC: renamed exactly once — new path present, no duplicate, and the
      // panel now shows the page name (rename field cleared, commit done).
      final pages = await listPages(vaultPath);
      expect(pages, contains(p.join('pages', 'entered.md')));
      expect(
        pages.where((e) => e.contains('untitled')).isEmpty,
        isTrue,
        reason: 'the suggested-name placeholder must be gone, not duplicated',
      );
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
      expect(
        tester.takeException(),
        isNull,
        reason: 'Escape cancel must not surface an error',
      );

      // AC: NOT committed — typed name absent, placeholder (untitled*) remains.
      final pages = await listPages(vaultPath);
      expect(
        pages.where((e) => e.contains('canceled')).isEmpty,
        isTrue,
        reason: 'Escape must cancel — the typed name must not be written',
      );
      expect(
        pages.where((e) => e.contains('untitled')).isNotEmpty,
        isTrue,
        reason: 'the created placeholder page must survive the cancel',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await parentDir.dispose();
    }
  });
}
