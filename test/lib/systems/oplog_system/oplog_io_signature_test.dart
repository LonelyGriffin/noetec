// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_reader.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';
import 'package:noetec/systems/oplog_system/oplog_verifier.dart';
import 'package:noetec/systems/oplog_system/oplog_writer.dart';

import '../../../helpers/test_fakes.dart';

/// In-memory filesystem with directory listing (mirrors the oplog IO tests).
class _FakeFs implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> dirs = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readFile(String path) async => files[path] ?? '';
  @override
  Future<void> writeFile(String path, String content) async => files[path] = content;
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
          entries.add(FileEntry(name: relative, path: key, isDirectory: false, lastModified: DateTime.now()));
        }
      }
    }
    return entries;
  }

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}
  @override
  Stream<FileEntry> watchDirectory(String path, {Duration pollInterval = const Duration(seconds: 5)}) => const Stream.empty();
}

void main() {
  const serializer = OpLogSerializer();
  final crypto = CryptoServiceImpl();

  group('OpLog sign-on-write / verify-on-read round-trip —', () {
    late _FakeFs fs;
    late OpLogWriter writer;
    late OpLogReader reader;
    late String pubKey;
    late String privKey;
    const deviceId = 'dev1-uuid-here-xxxx-xxxxxxxxxxxx';
    const vaultId = 'vault-1';
    const relPath = 'pages/notes/ideas.md';

    setUp(() async {
      fs = _FakeFs();
      final store = FakeSecureKeyStore();
      final pair = await crypto.generateDeviceKeyPair();
      pubKey = pair.publicKeyBase64Url;
      privKey = pair.privateKeyBase64Url;
      await store.storeDevicePrivateKey(vaultId, privKey);

      final signer = OpLogSigner(crypto: crypto, secureKeyStore: store, serializer: serializer);
      final verifier = OpLogVerifier(crypto: crypto, serializer: serializer, keyResolver: (d) async => d == deviceId ? pubKey : null);
      writer = OpLogWriter(fs, '/vault', serializer, signer: signer, vaultId: vaultId, devicePublicKeyBase64Url: pubKey);
      reader = OpLogReader(fs, '/vault', serializer, verifier: verifier);
    });

    test('every written entry carries a valid signature; the first entry carries pubKey', () async {
      final e1 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: null,
        fileHash: null,
        deviceId: deviceId,
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
        deviceId: deviceId,
      );
      final e3 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('300-0000-dev1'),
        parent: Hlc.fromKey('200-0000-dev1'),
        parentB: null,
        type: OpEntryType.save,
        blockOps: null,
        fileOp: null,
        fileHash: 'sha256:abc',
        deviceId: deviceId,
      );

      await writer.append(relPath, e1);
      await writer.append(relPath, e2);
      await writer.append(relPath, e3);

      final raw = fs.files['/vault/.sync/$relPath/$deviceId.oplog.jsonl']!;
      final lines = raw.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(3));

      final read = await reader.readDeviceLog(relPath, deviceId);
      expect(read, hasLength(3), reason: 'all valid signed entries must survive the read path');
      expect(read.first.pubKey, pubKey, reason: 'first entry must publish the device key');
      expect(read[1].pubKey, isNull, reason: 'later entries must not carry pubKey');
      expect(read.last.signature, isNotNull);
    });

    test('a forged entry written by an attacker is rejected on read, dropping its tail', () async {
      // Attacker key, different from the device that "owns" the file.
      final attacker = await crypto.generateDeviceKeyPair();
      final attackerStore = FakeSecureKeyStore();
      await attackerStore.storeDevicePrivateKey('attacker', attacker.privateKeyBase64Url);
      final attackerSigner = OpLogSigner(crypto: crypto, secureKeyStore: attackerStore, serializer: serializer);
      final attackerWriter = OpLogWriter(fs, '/vault', serializer, signer: attackerSigner, vaultId: 'attacker', devicePublicKeyBase64Url: attacker.publicKeyBase64Url);

      // A legitimate first entry (published pubKey = the *victim's* key).
      final legit = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: null,
        fileHash: null,
        deviceId: deviceId,
      );
      await writer.append(relPath, legit);

      // The attacker appends a "next" entry signed with their own key but
      // under the victim's deviceId.
      final forged = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: const [BlockDelete(blockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: deviceId,
      );
      await attackerWriter.append(relPath, forged);

      final read = await reader.readDeviceLog(relPath, deviceId);
      expect(read, hasLength(1), reason: 'the forged entry and anything after it must be rejected');
      expect(read.first.hlcKey, '100-0000-dev1');
    });

    test('a mixed legacy + signed file verifies correctly on read', () async {
      // Legacy (unsigned) first line — no pubKey, no signature.
      const legacyLine = '{"v":1,"hlc":"100-0000-dev1","parent":null,"type":"file_create","device":"dev1-uuid-here-xxxx-xxxxxxxxxxxx"}';
      await fs.appendToFile('/vault/.sync/$relPath/$deviceId.oplog.jsonl', '$legacyLine\n');
      // Ensure the directory exists for the writer.
      await fs.createDirectory('/vault/.sync/$relPath');

      // A signed second entry with no pubKey (mixed file) — verified via the
      // resolver (device.json key for the local device).
      final signed = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: const [BlockDelete(blockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: deviceId,
      );
      await writer.append(relPath, signed);

      final read = await reader.readDeviceLog(relPath, deviceId);
      expect(read, hasLength(2), reason: 'legacy entry is accepted (no chain rejection) and the signed entry verifies');
      expect(read.first.signature, isNull);
      expect(read.last.signature, isNotNull);
    });
  });
}
