import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_reader.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_writer.dart';

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

void main() {
  group('OpLogWriter', () {
    late _FakeFs fs;
    late OpLogSerializer serializer;
    late OpLogWriter writer;

    setUp(() {
      fs = _FakeFs();
      serializer = const OpLogSerializer();
      writer = OpLogWriter(fs, '/vault', serializer);
    });

    test('append writes entry to correct path', () async {
      final entry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(pageId: 'p1', initialBlocks: []),
        fileHash: null,
        deviceId: 'dev1',
      );

      await writer.append('pages/welcome.md', entry);

      const expectedPath =
          '/vault/.sync/pages/pages%2Fwelcome.md/dev1.oplog.jsonl';
      expect(fs.files.containsKey(expectedPath), isTrue);
    });

    test('multiple appends accumulate in same file', () async {
      final e1 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(pageId: 'p1', initialBlocks: []),
        fileHash: null,
        deviceId: 'dev1',
      );
      final e2 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: const [BlockDelete(blockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      await writer.append('pages/welcome.md', e1);
      await writer.append('pages/welcome.md', e2);

      const path = '/vault/.sync/pages/pages%2Fwelcome.md/dev1.oplog.jsonl';
      final lines = fs.files[path]!.split('\n').where((l) => l.isNotEmpty);
      expect(lines.length, 2);
    });
  });

  group('OpLogReader', () {
    late _FakeFs fs;
    late OpLogSerializer serializer;
    late OpLogWriter writer;
    late OpLogReader reader;

    setUp(() {
      fs = _FakeFs();
      serializer = const OpLogSerializer();
      writer = OpLogWriter(fs, '/vault', serializer);
      reader = OpLogReader(fs, '/vault', serializer);
    });

    test('readDeviceLog returns entries for specific device', () async {
      final entry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(pageId: 'p1', initialBlocks: []),
        fileHash: null,
        deviceId: 'dev1',
      );
      await writer.append('pages/welcome.md', entry);

      final entries = await reader.readDeviceLog('pages/welcome.md', 'dev1');
      expect(entries, hasLength(1));
      expect(entries.first.deviceId, 'dev1');
      expect(entries.first.type, OpEntryType.fileCreate);
    });

    test('readAllLogs returns entries from all devices', () async {
      final e1 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(pageId: 'p1', initialBlocks: []),
        fileHash: null,
        deviceId: 'dev1',
      );
      final e2 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev2'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: const [BlockDelete(blockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev2',
      );

      await writer.append('pages/welcome.md', e1);
      await writer.append('pages/welcome.md', e2);

      final allLogs = await reader.readAllLogs('pages/welcome.md');
      expect(allLogs.keys, contains('dev1'));
      expect(allLogs.keys, contains('dev2'));
    });
  });
}
