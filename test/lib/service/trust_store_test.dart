// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/trust_store.dart';

import '../../helpers/test_fakes.dart';

void main() {
  late FakeFileSystemService fs;
  late TrustStoreImpl store;
  final records = <LogRecord>[];
  late StreamSubscription<void> logSubscription;

  const vaultRoot = '/vault';
  const storePath = '/vault/.noetec/trusted_keys.json';
  const deviceA = 'device-a';
  const deviceB = 'device-b';
  const userA = 'user-a';
  const keyA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const keyAAlt = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const keyB = 'ccccccccccccccccccccccccccccccccccccccccc';

  // Route every log record (including the store's private
  // `Logger('trust_store')` records, which propagate to the root) into
  // [records] for the substitution-reporting assertions (spec §9).
  setUpAll(() {
    logSubscription = Logger.root.onRecord.listen(records.add);
  });

  tearDownAll(() => logSubscription.cancel());

  setUp(() {
    fs = FakeFileSystemService();
    records.clear();
    store = TrustStoreImpl(fs);
  });

  group('TrustStoreImpl — first observation (TOFU pinning) —', () {
    test('records an unseen key and persists it under .noetec/trusted_keys.json', () async {
      final decision = await store.observeKey(vaultRoot, deviceA, keyA);

      expect(decision, isA<TrustPinned>());
      expect((decision as TrustPinned).key, keyA);

      final fileContent = fs.files[storePath];
      expect(fileContent, isNotNull, reason: 'trusted_keys.json must be written under .noetec/');
      expect(jsonDecode(fileContent!), {deviceA: keyA});
    });

    test('empty store: every first observation is trusted (spec §8.4)', () async {
      expect(await store.observeKey(vaultRoot, deviceA, keyA), isA<TrustPinned>());
      expect(await store.observeKey(vaultRoot, deviceB, keyB), isA<TrustPinned>());
      expect(await store.observeKey(vaultRoot, userA, keyA), isA<TrustPinned>());
    });

    test('pinned keys survive a store reload (read-modify-write, not clobber)', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      await store.observeKey(vaultRoot, deviceB, keyB);

      final reloaded = TrustStoreImpl(fs);
      expect(await reloaded.pinnedKeys(vaultRoot), {deviceA: keyA, deviceB: keyB});
    });

    test('pinnedKeys returns an unmodifiable snapshot', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);

      final keys = await store.pinnedKeys(vaultRoot);
      expect(keys, {deviceA: keyA});
      expect(() => keys[deviceB] = keyB, throwsUnsupportedError);
    });
  });

  group('TrustStoreImpl — equal key (verify) —', () {
    test('observing the same key again verifies without rewriting the store', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      final firstWrite = fs.files[storePath];

      final decision = await store.observeKey(vaultRoot, deviceA, keyA);

      expect(decision, isA<TrustVerified>());
      expect((decision as TrustVerified).key, keyA);
      expect(fs.files[storePath], firstWrite, reason: 'a matching observation must not rewrite the store');
    });

    test('device and user ids share one key namespace per file', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      expect(await store.observeKey(vaultRoot, deviceA, keyA), isA<TrustVerified>());
      expect(await store.observeKey(vaultRoot, userA, keyA), isA<TrustPinned>());
    });
  });

  group('TrustStoreImpl — key substitution (spec §5.2 rule 3) —', () {
    test('a different key is rejected, both keys are logged, and the stored key stays authoritative', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);

      final decision = await store.observeKey(vaultRoot, deviceA, keyAAlt);

      expect(decision, isA<TrustSubstituted>());
      final substituted = decision as TrustSubstituted;
      expect(substituted.storedKey, keyA);
      expect(substituted.observedKey, keyAAlt);

      // The store must still hold the original key — the substitution is not
      // applied until the user confirms.
      expect(jsonDecode(fs.files[storePath]!), {deviceA: keyA});

      // Both keys are reported to the user via package:logging (spec §9).
      final mismatchRecords = records.where((r) => r.level == Level.WARNING && r.message.contains(keyA) && r.message.contains(keyAAlt)).toList();
      expect(mismatchRecords, isNotEmpty, reason: 'key substitution must be logged with both keys');
    });

    test('repeat substitution observations stay rejected while the stored key is unchanged', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      await store.observeKey(vaultRoot, deviceA, keyAAlt);

      expect(await store.observeKey(vaultRoot, deviceA, keyAAlt), isA<TrustSubstituted>());
      expect(jsonDecode(fs.files[storePath]!), {deviceA: keyA});
    });

    test('observing the original key after a substitution verifies normally', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      await store.observeKey(vaultRoot, deviceA, keyAAlt);

      expect(await store.observeKey(vaultRoot, deviceA, keyA), isA<TrustVerified>());
    });

    test('confirmKey adopts the new key, persists it, and subsequent observation verifies', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);
      await store.observeKey(vaultRoot, deviceA, keyAAlt);

      await store.confirmKey(vaultRoot, deviceA, keyAAlt);

      expect(jsonDecode(fs.files[storePath]!), {deviceA: keyAAlt});
      expect(await store.observeKey(vaultRoot, deviceA, keyAAlt), isA<TrustVerified>());
    });

    test('confirmKey throws for an identifier that was never pinned', () async {
      expect(() => store.confirmKey(vaultRoot, deviceA, keyA), throwsArgumentError);
      // A failed confirmation leaves the store untouched.
      expect(fs.files.containsKey(storePath), isFalse);
    });
  });

  group('TrustStoreImpl — file location and format —', () {
    test('the store file is created under .noetec/, never under .sync/', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);

      expect(fs.files.keys, contains(storePath));
      expect(fs.files.keys.where((p) => p.contains('/.sync/')), isEmpty);
    });

    test('the store is per-vault: a second vault starts empty', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);

      expect(await store.pinnedKeys('/other-vault'), isEmpty);
    });

    test('a malformed store file throws FormatException instead of silently re-arming trust', () async {
      fs.files[storePath] = 'not json at all';

      expect(() => store.observeKey(vaultRoot, deviceA, keyA), throwsFormatException);
    });

    test('a non-object store file throws FormatException', () async {
      fs.files[storePath] = jsonEncode(['a-list']);

      expect(() => store.pinnedKeys(vaultRoot), throwsFormatException);
    });

    test('a store entry that is not a string value throws FormatException', () async {
      fs.files[storePath] = jsonEncode({'device-a': 42});

      expect(() => store.pinnedKeys(vaultRoot), throwsFormatException);
    });
  });

  group('TrustStoreImpl — reset (spec §5.3) —', () {
    test('reset removes the store and re-arms first-observation trust', () async {
      await store.observeKey(vaultRoot, deviceA, keyA);

      await store.reset(vaultRoot);

      expect(fs.files.containsKey(storePath), isFalse);
      expect(await store.observeKey(vaultRoot, deviceA, keyA), isA<TrustPinned>());
    });

    test('reset is a no-op for a vault without a store file', () async {
      await store.reset(vaultRoot);
      expect(fs.files, isEmpty);
    });
  });

  group('TrustStoreImpl — concurrent observations (per-vault lock) —', () {
    test('concurrent first observations on one vault do not lose a pin', () async {
      // A file system that yields to the event loop inside readFile/writeFile,
      // so the three read-modify-write cycles interleave. A broken per-vault
      // lock (head registered *after* awaiting the predecessor) lets two
      // observers read the same store and the later write clobbers the
      // earlier pin.
      final concurrentFs = _YieldingFileSystemService();
      final concurrentStore = TrustStoreImpl(concurrentFs);

      final decisions = await Future.wait([
        concurrentStore.observeKey(vaultRoot, deviceA, keyA),
        concurrentStore.observeKey(vaultRoot, deviceB, keyB),
        concurrentStore.observeKey(vaultRoot, userA, keyAAlt),
      ]);

      // Every one of these is a first sighting, so each reports TrustPinned.
      expect(decisions, everyElement(isA<TrustPinned>()));

      // The discriminating check: none of the three pins may be lost to the
      // read-modify-write race.
      expect(await concurrentStore.pinnedKeys(vaultRoot), {deviceA: keyA, deviceB: keyB, userA: keyAAlt});
    });
  });
}

/// An in-memory [IFileSystemService] that yields a macro-task inside
/// [readFile] and [writeFile], widening the read-modify-write window so that
/// concurrent calls interleave deterministically. Used to prove that the
/// trust store's per-vault lock actually provides mutual exclusion.
class _YieldingFileSystemService implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> dirs = {};

  Future<void> _yield() => Future<void>.delayed(Duration.zero);

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<String> readFile(String path) async {
    await _yield();
    return files[path] ?? '';
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await _yield();
    files[path] = content;
  }

  @override
  Future<void> appendToFile(String path, String content) async {
    await _yield();
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
  Future<List<FileEntry>> listDirectory(String path) async => [];

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}

  @override
  Stream<FileEntry> watchDirectory(String path, {Duration pollInterval = const Duration(seconds: 5)}) => const Stream.empty();
}
