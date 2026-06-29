import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/file_system_service.dart';
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
  Future<void> writeFile(String path, String content) async {
    files[path] = content;
  }

  @override
  Future<void> appendToFile(String path, String content) async {
    files[path] = (files[path] ?? '') + content;
  }

  @override
  Future<void> deleteFile(String path) async => files.remove(path);

  @override
  Future<bool> directoryExists(String path) async => dirs.contains(path);

  @override
  Future<void> createDirectory(String path) async => dirs.add(path);

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final normalized = path.replaceAll('\\', '/');
    final entries = <FileEntry>[];
    for (final key in files.keys) {
      final normKey = key.replaceAll('\\', '/');
      if (normKey.startsWith('$normalized/')) {
        final relative = normKey.substring(normalized.length + 1);
        if (!relative.contains('/')) {
          entries.add(
            FileEntry(
              name: relative,
              path: key,
              isDirectory: false,
              lastModified: DateTime.now(),
            ),
          );
        }
      }
    }
    for (final dir in dirs) {
      if (dir.startsWith('$normalized/')) {
        final relative = dir.substring(normalized.length + 1);
        if (!relative.contains('/')) {
          entries.add(FileEntry(name: relative, path: dir, isDirectory: true));
        }
      }
    }
    return entries;
  }

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}

  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();
}

void main() {
  group('WalService —', () {
    late _FakeFs fs;
    late VaultSystem vaultSystem;
    late WalService wal;

    setUp(() {
      fs = _FakeFs();
      fs.dirs.add('/vault/.noetec/wal');
      vaultSystem = createTestVaultSystem();
      wal = WalService(fs, vaultSystem);

      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );
    });

    tearDown(() {
      wal.dispose();
      vaultSystem.dispose();
    });

    test('register and appendAction writes WAL file after flush', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'hi'),
      );

      await wal.flush('page1');

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, hasLength(1));
    });

    test('clear deletes WAL file', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'x'),
      );
      await wal.flush('page1');
      await wal.clear('page1');

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, isEmpty);
    });

    test('readWal returns deserialized actions', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'test'),
      );
      await wal.flush('page1');

      final pending = await wal.getPendingWals();
      expect(pending, hasLength(1));
      final actions = await wal.readWal(pending.first.walFilePath);
      expect(actions, hasLength(1));
      expect(actions.first, isA<InsertTextAction>());
    });

    test(
      'accumulates consecutive InsertText with same block and contiguous offset',
      () async {
        wal.register('page1', 'pages/welcome.md');
        wal.appendAction(
          'page1',
          const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'h'),
        );
        wal.appendAction(
          'page1',
          const InsertTextAction(blockId: 'b1', flatOffset: 1, text: 'i'),
        );

        await wal.flush('page1');

        final pending = await wal.getPendingWals();
        final actions = await wal.readWal(pending.first.walFilePath);
        expect(actions, hasLength(1));
        expect((actions.first as InsertTextAction).text, 'hi');
      },
    );

    test('does not accumulate InsertText with different blocks', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b2', flatOffset: 0, text: 'b'),
      );

      await wal.flush('page1');

      final pending = await wal.getPendingWals();
      final actions = await wal.readWal(pending.first.walFilePath);
      expect(actions, hasLength(2));
    });

    test(
      'accumulates consecutive DeleteTextBack with decreasing offset',
      () async {
        wal.register('page1', 'pages/welcome.md');
        wal.appendAction(
          'page1',
          const DeleteTextBackAction(blockId: 'b1', flatOffset: 10),
        );
        wal.appendAction(
          'page1',
          const DeleteTextBackAction(blockId: 'b1', flatOffset: 9),
        );
        wal.appendAction(
          'page1',
          const DeleteTextBackAction(blockId: 'b1', flatOffset: 8),
        );

        await wal.flush('page1');

        final pending = await wal.getPendingWals();
        final actions = await wal.readWal(pending.first.walFilePath);
        expect(actions, hasLength(1));
        expect(actions.first, isA<DeleteTextBackAction>());
      },
    );

    test(
      'accumulates consecutive DeleteTextForward with same offset',
      () async {
        wal.register('page1', 'pages/welcome.md');
        wal.appendAction(
          'page1',
          const DeleteTextForwardAction(blockId: 'b1', flatOffset: 5),
        );
        wal.appendAction(
          'page1',
          const DeleteTextForwardAction(blockId: 'b1', flatOffset: 5),
        );

        await wal.flush('page1');

        final pending = await wal.getPendingWals();
        final actions = await wal.readWal(pending.first.walFilePath);
        expect(actions, hasLength(1));
      },
    );

    test('unregister removes page from tracking', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.unregister('page1');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'x'),
      );
      await wal.flush('page1');

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, isEmpty);
    });

    test('clearAll removes all WAL files and buffers', () async {
      wal.register('page1', 'pages/a.md');
      wal.register('page2', 'pages/b.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );
      wal.appendAction(
        'page2',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'b'),
      );
      await wal.flush('page1');
      await wal.flush('page2');

      await wal.clearAll();

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, isEmpty);
    });

    test('getPendingWals returns WalEntry for each WAL file', () async {
      wal.register('page1', 'pages/welcome.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );
      await wal.flush('page1');

      final pending = await wal.getPendingWals();
      expect(pending, hasLength(1));
      expect(pending.first.relativePath, 'pages/welcome.md');
    });

    test('WAL path uses URI-encoded relative path', () async {
      wal.register('page1', 'pages/notes/idea.md');
      wal.appendAction(
        'page1',
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'x'),
      );
      await wal.flush('page1');

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, hasLength(1));
      expect(walFiles.first.contains('pages%2Fnotes%2Fidea'), isTrue);
    });

    test('flush with no pending actions is no-op', () async {
      wal.register('page1', 'pages/welcome.md');
      await wal.flush('page1');

      final walFiles = fs.files.keys
          .where((k) => k.endsWith('.wal.jsonl'))
          .toList();
      expect(walFiles, isEmpty);
    });

    test('readWal returns empty list for non-existent file', () async {
      final actions = await wal.readWal(
        '/vault/.noetec/wal/nonexistent.wal.jsonl',
      );
      expect(actions, isEmpty);
    });
  });
}
