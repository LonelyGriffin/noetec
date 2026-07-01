import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/persistence_system/persistence_system.dart';
import 'package:noetec/systems/persistence_system/wal_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../../helpers/test_fakes.dart';

class _FakeFs implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> dirs = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readFile(String path) async => files[path] ?? '';
  @override
  Future<void> writeFile(String path, String content) async =>
      files[path] = content;
  @override
  Future<void> appendToFile(String path, String content) async =>
      files[path] = (files[path] ?? '') + content;
  @override
  Future<void> deleteFile(String path) async => files.remove(path);
  @override
  Future<bool> directoryExists(String path) async => dirs.contains(path);
  @override
  Future<void> createDirectory(String path) async => dirs.add(path);
  @override
  Future<String?> pickDirectory() async => null;
  @override
  Future<List<FileEntry>> listDirectory(String path) async => [];
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}
  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();
}

void main() {
  group('PersistenceSystem —', () {
    late _FakeFs fs;
    late VaultSystem vaultSystem;
    late PageSystem pageSystem;
    late WalService walService;
    late PersistenceSystem persistenceSystem;
    late String testPageId;

    setUp(() async {
      fs = _FakeFs();
      fs.dirs.add('/vault/.noetec/wal');
      fs.files['/vault/pages/welcome.md'] = '''---
id: page1
content_hash: ''
modified: 2026-01-01T00:00:00.000Z
---
Hello world''';
      vaultSystem = createTestVaultSystem();
      pageSystem = PageSystem(
        FakeIdService(),
        MarkdownSystem(FakeIdService()),
        fs,
        vaultSystem,
      );
      walService = WalService(fs, vaultSystem);

      final hlcService = HlcService(vaultSystem, FakeDeviceService());
      final realOplog = OpLogSystem(
        fileSystem: fs,
        hlcService: hlcService,
        vaultSystem: vaultSystem,
        deviceService: FakeDeviceService(),
      );

      persistenceSystem = PersistenceSystem(
        wal: walService,
        oplog: realOplog,
        pageSystem: pageSystem,
        vaultSystem: vaultSystem,
      );

      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );

      await pageSystem.loadPage('pages/welcome.md');
      testPageId = pageSystem.openPages.keys.first;
    });

    tearDown(() {
      persistenceSystem.dispose();
      walService.dispose();
      pageSystem.dispose();
      vaultSystem.dispose();
    });

    test('page load creates clean state', () {
      expect(pageSystem.openPages.keys.toList(), contains(testPageId));
      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.clean,
      );
    });

    test('action dispatch marks page dirty', () {
      pageSystem.activePageId.value = testPageId;

      pageSystem.actionDispatcher.dispatch(
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );

      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.dirty,
      );
    });

    test('savePage transitions dirty → saving → clean', () async {
      pageSystem.activePageId.value = testPageId;

      pageSystem.actionDispatcher.dispatch(
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );
      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.dirty,
      );

      await persistenceSystem.savePage(testPageId);

      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.clean,
      );
      expect(
        persistenceSystem.saveStateOf(testPageId).value.lastSaved,
        isNotNull,
      );
    });

    test('savePage on clean page is no-op', () async {
      await persistenceSystem.savePage(testPageId);

      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.clean,
      );
    });

    test('closePage removes state notifier', () async {
      pageSystem.closePage(testPageId);

      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.clean,
      );
    });

    test('markDirty explicitly sets dirty state', () {
      persistenceSystem.markDirty(testPageId);

      expect(
        persistenceSystem.saveStateOf(testPageId).value.state,
        PageSaveState.dirty,
      );
    });
  });

  group('PageSaveInfo —', () {
    test('default state is clean', () {
      const info = PageSaveInfo();
      expect(info.state, PageSaveState.clean);
      expect(info.lastSaved, isNull);
      expect(info.lastError, isNull);
    });

    test('copyWith creates new instance', () {
      const info = PageSaveInfo();
      final updated = info.copyWith(
        state: PageSaveState.dirty,
        lastSaved: DateTime(2026, 1, 1),
      );
      expect(updated.state, PageSaveState.dirty);
      expect(updated.lastSaved, DateTime(2026, 1, 1));
      expect(info.state, PageSaveState.clean);
    });
  });
}
