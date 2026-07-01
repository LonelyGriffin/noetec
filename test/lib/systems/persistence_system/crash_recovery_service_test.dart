import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/persistence_system/crash_recovery_service.dart';
import 'package:noetec/systems/persistence_system/wal_action_serializer.dart';
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
  Future<List<FileEntry>> listDirectory(String path) async {
    final normalized = path.replaceAll('\\', '/');
    final entries = <FileEntry>[];
    final seen = <String>{};
    for (final key in files.keys) {
      final normKey = key.replaceAll('\\', '/');
      if (normKey.startsWith('$normalized/')) {
        final relative = normKey.substring(normalized.length + 1);
        final slashIndex = relative.indexOf('/');
        if (slashIndex < 0) {
          entries.add(
            FileEntry(
              name: relative,
              path: key,
              isDirectory: false,
              lastModified: DateTime.now(),
            ),
          );
        } else {
          final dirName = relative.substring(0, slashIndex);
          if (seen.add(dirName)) {
            entries.add(
              FileEntry(
                name: dirName,
                path: '$normalized/$dirName',
                isDirectory: true,
              ),
            );
          }
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
  group('CrashRecoveryService —', () {
    late _FakeFs fs;
    late VaultSystem vaultSystem;
    late WalService walService;
    late CrashRecoveryService recoveryService;

    setUp(() {
      fs = _FakeFs();
      fs.dirs.add('/vault/.noetec/wal');
      vaultSystem = createTestVaultSystem();
      walService = WalService(fs, vaultSystem);
      recoveryService = CrashRecoveryService(walService);

      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );
    });

    tearDown(() {
      walService.dispose();
      vaultSystem.dispose();
    });

    test('findCandidates returns empty when no WAL files exist', () async {
      final candidates = await recoveryService.findCandidates();
      expect(candidates, isEmpty);
    });

    test('findCandidates returns candidate for leftover WAL', () async {
      const serializer = WalActionSerializer();
      const action = InsertTextAction(
        blockId: 'b1',
        flatOffset: 0,
        text: 'hello',
      );
      final json = serializer.toJson(action);
      json['ts'] = DateTime.now().millisecondsSinceEpoch;

      fs.files['/vault/.noetec/wal/pages/welcome.md'] = '${jsonEncode(json)}\n';

      final candidates = await recoveryService.findCandidates();
      expect(candidates, hasLength(1));
      expect(candidates.first.relativePath, 'pages/welcome.md');
      expect(candidates.first.pendingActions, hasLength(1));
      expect(candidates.first.pendingActions.first, isA<InsertTextAction>());
    });

    test('discardAll removes all WAL files', () async {
      const serializer = WalActionSerializer();
      const action = InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'x');
      final json = serializer.toJson(action);

      fs.files['/vault/.noetec/wal/pages/welcome.md'] = '${jsonEncode(json)}\n';

      await recoveryService.discardAll();

      final walFiles = fs.files.keys
          .where((k) => k.startsWith('/vault/.noetec/wal/'))
          .toList();
      expect(walFiles, isEmpty);
    });
  });
}
