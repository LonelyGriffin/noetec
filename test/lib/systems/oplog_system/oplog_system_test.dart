import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
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

TextBlockEntity _block(String id, String text) => TextBlockEntity(
  id: id,
  segments: [TextSegment(text: text)],
);

void main() {
  group('OpLogSystem', () {
    late _FakeFs fs;
    late VaultSystem vaultSystem;
    late FakeDeviceService deviceService;
    late HlcService hlcService;
    late OpLogSystem opLog;

    setUp(() {
      fs = _FakeFs();
      deviceService = FakeDeviceService();
      deviceService.setDevice(
        DeviceIdentity(
          uuid: 'dev1-uuid-here-xxxx-xxxxxxxxxxxx',
          name: 'Test Device',
          createdAt: DateTime(2026),
          lastHlc: null,
          publicKey: 'test-key',
        ),
      );
      vaultSystem = createTestVaultSystem(deviceService: deviceService);
      hlcService = HlcService(vaultSystem, deviceService);
      opLog = OpLogSystem(
        fileSystem: fs,
        hlcService: hlcService,
        vaultSystem: vaultSystem,
        deviceService: deviceService,
      );

      vaultSystem.currentVault.value = VaultEntity(
        id: 'vault-1',
        name: 'TestVault',
        rootPath: '/vault',
        createdAt: DateTime(2026),
      );
    });

    tearDown(() {
      opLog.dispose();
      hlcService.dispose();
      vaultSystem.dispose();
    });

    test('recordFileCreate writes file_create entry to oplog', () async {
      final blocks = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', blocks);

      final dag = await opLog.buildDag('pages/welcome.md');
      expect(dag.sortedEntries, hasLength(1));
      expect(dag.sortedEntries.first.type, OpEntryType.fileCreate);
    });

    test('recordSave writes edit + save when blocks changed', () async {
      final initial = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', initial);
      opLog.initLastKnownState('page1', initial);

      final updated = [_block('b1', 'Hello World')];
      await opLog.recordSave(
        'pages/welcome.md',
        'page1',
        updated,
        'sha256:abc',
      );

      final dag = await opLog.buildDag('pages/welcome.md');
      final entries = dag.sortedEntries;
      expect(entries.length, 3);
      expect(entries[1].type, OpEntryType.edit);
      expect(entries[2].type, OpEntryType.save);
    });

    test('recordSave writes only save when no changes detected', () async {
      final blocks = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', blocks);
      opLog.initLastKnownState('page1', blocks);

      await opLog.recordSave('pages/welcome.md', 'page1', blocks, 'sha256:abc');

      final dag = await opLog.buildDag('pages/welcome.md');
      final entries = dag.sortedEntries;
      expect(entries.length, 2);
      expect(entries.last.type, OpEntryType.save);
    });

    test('recordFileDelete writes file_delete entry', () async {
      final blocks = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', blocks);

      await opLog.recordFileDelete('pages/welcome.md');

      final dag = await opLog.buildDag('pages/welcome.md');
      final entries = dag.sortedEntries;
      expect(entries.last.type, OpEntryType.fileDelete);
    });

    test('recordFileRename writes file_rename entry at new path', () async {
      final blocks = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/old.md', 'page1', blocks);

      await opLog.recordFileRename('pages/old.md', 'pages/new.md');

      final dag = await opLog.buildDag('pages/new.md');
      final entries = dag.sortedEntries;
      expect(entries.last.type, OpEntryType.fileRename);
    });

    test('recordExternalEdit writes external_edit with diff', () async {
      final initial = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', initial);
      opLog.initLastKnownState('page1', initial);

      final edited = [_block('b1', 'Hello Modified')];
      await opLog.recordExternalEdit(
        'pages/welcome.md',
        edited,
        'sha256:def',
        pageId: 'page1',
      );

      final dag = await opLog.buildDag('pages/welcome.md');
      final entries = dag.sortedEntries;
      expect(entries.last.type, OpEntryType.externalEdit);
      expect(entries.last.blockOps, isNotEmpty);
    });

    test('recordMerge writes merge entry with two parents', () async {
      final blocks = [_block('b1', 'Hello')];
      await opLog.recordFileCreate('pages/welcome.md', 'page1', blocks);

      const parentA = Hlc(physicalMs: 100, counter: 0, deviceId: 'dev1');
      const parentB = Hlc(physicalMs: 200, counter: 0, deviceId: 'dev2');

      await opLog.recordMerge(
        'pages/welcome.md',
        parentA,
        parentB,
        'sha256:merged',
      );

      final dag = await opLog.buildDag('pages/welcome.md');
      final entries = dag.sortedEntries;
      expect(entries.last.type, OpEntryType.merge);
      expect(entries.last.parent, parentA);
      expect(entries.last.parentB, parentB);
    });

    test('buildDag returns DagTopology.empty for unknown file', () async {
      final dag = await opLog.buildDag('pages/nonexistent.md');
      expect(dag.topology, DagTopology.empty);
    });

    test('initLastKnownState caches blocks for diffing', () {
      final blocks = [_block('b1', 'Hello')];
      opLog.initLastKnownState('page1', blocks);
      expect(opLog.hasLastKnownState('page1'), isTrue);
    });

    test('clearLastKnownState removes cached blocks', () {
      final blocks = [_block('b1', 'Hello')];
      opLog.initLastKnownState('page1', blocks);
      opLog.clearLastKnownState('page1');
      expect(opLog.hasLastKnownState('page1'), isFalse);
    });
  });
}
