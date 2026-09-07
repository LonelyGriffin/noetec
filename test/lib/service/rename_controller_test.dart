// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/page_file_name_sanitizer.dart';
import 'package:noetec/service/rename_controller.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../helpers/test_fakes.dart';

/// [VaultFileService] whose [VaultFileService.renamePage] is recorded and can
/// be scripted to fail, so the tests can assert exactly how many times the
/// rename is invoked regardless of the (fake) file system.
class _RecordingVaultFileService extends VaultFileService {
  _RecordingVaultFileService(
    super.fileSystem,
    super.vaultSystem,
    super.pageSystem,
  );

  final List<List<String>> renameCalls = [];
  Exception Function()? _onRename;

  void whenRename(Exception Function() producer) => _onRename = producer;

  @override
  Future<String> renamePage(
    String vaultRootPath,
    String oldRelativePath,
    String newFileName,
  ) async {
    renameCalls.add([oldRelativePath, newFileName]);
    final producer = _onRename;
    if (producer != null) throw producer();
    return 'pages/${newFileName.trim()}.md';
  }
}

void main() {
  const oldPath = 'pages/old.md';
  final vault = VaultEntity(
    id: 'vault-1',
    name: 'TestVault',
    rootPath: '/vault',
    createdAt: DateTime(2026),
  );

  late VaultSystem vaultSystem;
  late _RecordingVaultFileService vfs;
  late RenameController controller;

  setUp(() {
    vaultSystem = createTestVaultSystem();
    final pageSystem = PageSystem(
      FakeIdService(),
      MarkdownSystem(FakeIdService()),
      FakeFileSystemService(),
      vaultSystem,
    );
    vfs = _RecordingVaultFileService(
      FakeFileSystemService(),
      vaultSystem,
      pageSystem,
    );
    controller = RenameController(vfs, vaultSystem);
    vaultSystem.currentVault.value = vault;
  });

  tearDown(() {
    controller.dispose();
    vaultSystem.currentVault.value = null;
    vaultSystem.dispose();
  });

  group('RenameController — commit-once invariant (NOET-17)', () {
    test(
      'confirmCommand renames exactly once (Enter + focus-loss both fire it)',
      () async {
        await controller.beginCommand.runAsync(oldPath);
        await controller.confirmCommand.runAsync('renamed');
        // A second confirm (the focus-loss re-entry) must be a no-op.
        await controller.confirmCommand.runAsync('renamed');
        expect(vfs.renameCalls, hasLength(1));
      },
    );

    test('two concurrent confirmCommands still rename exactly once', () async {
      await controller.beginCommand.runAsync(oldPath);
      // Simulate Enter (onSubmitted) racing the focus-loss handler: both
      // confirm before either has settled.
      await Future.wait([
        controller.confirmCommand.runAsync('renamed'),
        controller.confirmCommand.runAsync('renamed'),
      ]);
      expect(vfs.renameCalls, hasLength(1));
    });

    test('a confirm after the session is closed is a no-op', () async {
      await controller.beginCommand.runAsync(oldPath);
      await controller.cancelCommand.runAsync();
      await controller.confirmCommand.runAsync('renamed');
      expect(vfs.renameCalls, isEmpty);
      expect(controller.activePath.value, isNull);
    });

    test('cancelCommand abandons the session without renaming', () async {
      await controller.beginCommand.runAsync(oldPath);
      expect(controller.activePath.value, oldPath);

      await controller.cancelCommand.runAsync();

      expect(vfs.renameCalls, isEmpty);
      expect(controller.activePath.value, isNull);
    });

    test('an empty name closes the session without renaming', () async {
      await controller.beginCommand.runAsync(oldPath);
      await controller.confirmCommand.runAsync('   ');

      expect(vfs.renameCalls, isEmpty);
      expect(controller.activePath.value, isNull);
    });

    test('confirming with no active vault closes without renaming', () async {
      await controller.beginCommand.runAsync(oldPath);
      vaultSystem.currentVault.value = null;

      await controller.confirmCommand.runAsync('renamed');

      expect(vfs.renameCalls, isEmpty);
      expect(controller.activePath.value, isNull);
    });

    test('opening/closing the vault clears an armed session', () async {
      await controller.beginCommand.runAsync(oldPath);
      expect(controller.activePath.value, oldPath);

      vaultSystem.currentVault.value = null;
      expect(controller.activePath.value, isNull);
      expect(vfs.renameCalls, isEmpty);
    });

    test('confirming when no session is armed is a no-op', () async {
      await controller.confirmCommand.runAsync('renamed');
      expect(vfs.renameCalls, isEmpty);
      expect(controller.activePath.value, isNull);
    });
  });

  group('RenameController — real rename errors still propagate', () {
    test(
      'PageNameConflictException propagates and closes the session',
      () async {
        vfs.whenRename(() => const PageNameConflictException('renamed.md'));
        await controller.beginCommand.runAsync(oldPath);
        // Local listener mirrors how the app consumes command errors (via
        // `.errors`); it also satisfies command_it's local-handler routing.
        controller.confirmCommand.errors.addListener(() {});

        await expectLater(
          controller.confirmCommand.runAsync('renamed'),
          throwsA(isA<PageNameConflictException>()),
        );

        expect(controller.activePath.value, isNull);
        expect(vfs.renameCalls, hasLength(1));
      },
    );

    test(
      'PageNameInvalidException propagates and closes the session',
      () async {
        vfs.whenRename(() => const PageNameInvalidException('..'));
        await controller.beginCommand.runAsync(oldPath);
        controller.confirmCommand.errors.addListener(() {});

        await expectLater(
          controller.confirmCommand.runAsync('..'),
          throwsA(isA<PageNameInvalidException>()),
        );

        expect(controller.activePath.value, isNull);
        expect(vfs.renameCalls, hasLength(1));
      },
    );
  });
}
