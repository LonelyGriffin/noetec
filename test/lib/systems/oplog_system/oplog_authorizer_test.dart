// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/trust_store.dart';
import 'package:noetec/systems/oplog_system/oplog_authorizer.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../../helpers/test_fakes.dart';

Hlc _h(int ms, String dev) => Hlc(physicalMs: ms, counter: 0, deviceId: dev);

/// A minimal oplog entry (no blocks/file op). [pubKey] is set on the first
/// entry of a device file per sync-security.md §2.3; `null` for legacy or
/// non-first entries.
OpLogEntry _entry({required Hlc hlc, required String device, String? pubKey, Hlc? parent}) => OpLogEntry(
  version: 1,
  hlc: hlc,
  parent: parent,
  parentB: null,
  type: parent == null ? OpEntryType.fileCreate : OpEntryType.edit,
  blockOps: null,
  fileOp: null,
  fileHash: null,
  deviceId: device,
  signature: null,
  pubKey: pubKey,
);

/// A stub registry: returns the given `users.json` and per-user device files
/// directly (the real [IRegistryService] verifies their signatures — NOET-29;
/// the gate trusts that and only inspects the bindings).
final class _FakeRegistry implements IRegistryService {
  _FakeRegistry({this.users, this.devices = const {}});

  final UserRegistry? users;
  final Map<String, DeviceRegistry> devices;

  @override
  Future<UserRegistry?> loadUserRegistry() async => users;

  @override
  Future<DeviceRegistry?> loadDeviceRegistry(String userId) async => devices[userId];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A [_FakeRegistry] that counts how often its load methods are called —
/// used to prove the gate reads the registry once per sync cycle, not once
/// per oplog file (NOET-31 review: registry snapshot memoization).
final class _CountingRegistry extends _FakeRegistry {
  _CountingRegistry({required super.users, required super.devices});

  int loadUserRegistryCalls = 0;
  int loadDeviceRegistryCalls = 0;

  @override
  Future<UserRegistry?> loadUserRegistry() async {
    loadUserRegistryCalls++;
    return super.loadUserRegistry();
  }

  @override
  Future<DeviceRegistry?> loadDeviceRegistry(String userId) async {
    loadDeviceRegistryCalls++;
    return super.loadDeviceRegistry(userId);
  }
}

/// TOFU store that pins on first observation and reports substitution on a
/// differing key (mirrors [TrustStoreImpl]'s decision logic without a file).
final class _FakeTrustStore implements ITrustStore {
  _FakeTrustStore({this.throwOnObserve = false});

  /// When true, [observeKey] throws (models a malformed `trusted_keys.json`,
  /// §8.4) so the gate's trust-store-error path can be exercised.
  final bool throwOnObserve;

  final Map<String, String> pinned = {};

  @override
  Future<TrustDecision> observeKey(String vaultRootPath, String identifier, String publicKeyBase64Url) async {
    if (throwOnObserve) {
      throw const FormatException('trusted_keys.json is malformed');
    }
    final stored = pinned[identifier];
    if (stored == null) {
      pinned[identifier] = publicKeyBase64Url;
      return TrustPinned(key: publicKeyBase64Url);
    }
    if (stored == publicKeyBase64Url) return TrustVerified(key: stored);
    return TrustSubstituted(storedKey: stored, observedKey: publicKeyBase64Url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// In-memory filesystem with directory listing (mirrors the oplog IO tests).
final class _FakeFs implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> dirs = {};

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readFile(String path) async => files[path] ?? '';
  @override
  Future<void> writeFile(String path, String content) async => files[path] = content;
  @override
  Future<void> appendToFile(String path, String content) async => files[path] = (files[path] ?? '') + content;
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

UserRegistry _users(List<UserRecord> records, {Hlc? revision, Hlc? parent}) =>
    UserRegistry(version: 1, revision: revision ?? _h(1000, 'o'), parent: parent, ownerUserId: records.first.userId, users: records, signature: '');

UserRecord _user(String id, {String? publicKey, Hlc? updatedAt, Hlc? removedAt, bool owner = false}) => UserRecord(
  userId: id,
  name: id,
  publicKey: publicKey ?? 'pk-$id',
  role: owner ? 'owner' : 'member',
  addedBy: id,
  updatedAt: updatedAt ?? _h(1, 'o'),
  removedAt: removedAt,
  signature: '',
);

DeviceRegistry _devices(String userId, List<DeviceRecord> records) =>
    DeviceRegistry(version: 1, revision: _h(2000, 'o'), parent: null, userId: userId, devices: records, signature: '');

DeviceRecord _device(String uuid, String pub, {String userId = 'alice', Hlc? removedAt}) =>
    DeviceRecord(deviceUuid: uuid, devicePublicKey: pub, userId: userId, deviceName: 'd', issuedAt: _h(2, 'o'), updatedAt: _h(2, 'o'), removedAt: removedAt, signature: '');

void main() {
  final crypto = CryptoServiceImpl();

  group('OpLogAuthorizer (NOET-31 verification gate, §7 steps 3–5) —', () {
    const vault = '/vault';
    const relPath = 'pages/notes/ideas.md';

    test('a bound device of an authorized user is accepted (attribution chain holds)', () async {
      final pair = await crypto.generateDeviceKeyPair();
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice')]),
        devices: {
          'alice': _devices('alice', [_device('devA', pair.publicKeyBase64Url)]),
        },
      );
      final store = _FakeTrustStore();
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: store);

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA', pubKey: pair.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted.containsKey('devA'), isTrue);
      expect(outcome.rejections, isEmpty);
      expect(store.pinned['devA'], pair.publicKeyBase64Url, reason: 'TOFU pins the first observed device key');
    });

    test('a device not in any devices/<userId>.json is rejected (forged device)', () async {
      final attacker = await crypto.generateDeviceKeyPair();
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice')]),
        devices: {
          'alice': _devices('alice', [_device('devA', 'some-other-key')]),
        },
      );
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: _FakeTrustStore());

      // The attacker's device is bound to no user by a certificate whose key
      // matches, so its entries are rejected even though its own key verifies.
      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'attacker': [_entry(hlc: _h(150, 'atk'), device: 'attacker', pubKey: attacker.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections, hasLength(1));
      expect(outcome.rejections.single.reason, 'unbound-device');
      expect(outcome.rejections.single.devices, ['attacker']);
    });

    test('a device bound to a user absent from users.json is rejected', () async {
      final bob = await crypto.generateDeviceKeyPair();
      // 'bob' is bound in a device file but is absent from users.json, so his
      // device file is not loaded as a registry → the device is unbound.
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice')]),
        devices: {
          'bob': _devices('bob', [_device('bobdev', bob.publicKeyBase64Url, userId: 'bob')]),
        },
      );
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: _FakeTrustStore());

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'bobdev': [_entry(hlc: _h(150, 'bob'), device: 'bobdev', pubKey: bob.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections.single.reason, 'unbound-device');
    });

    test('a device bound to a revoked user is rejected as unauthorized', () async {
      final pair = await crypto.generateDeviceKeyPair();
      // 'alice' is revoked (removedAt set) but her device file still lists her device.
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice', removedAt: _h(3, 'o'))]),
        devices: {
          'alice': _devices('alice', [_device('devA', pair.publicKeyBase64Url)]),
        },
      );
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: _FakeTrustStore());

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA', pubKey: pair.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections.single.reason, 'unauthorized-user');
    });

    test('key substitution (TOFU mismatch) is rejected', () async {
      final pair = await crypto.generateDeviceKeyPair();
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice')]),
        devices: {
          'alice': _devices('alice', [_device('devA', pair.publicKeyBase64Url)]),
        },
      );
      final store = _FakeTrustStore()..pinned['devA'] = 'the-original-key';
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: store);

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA', pubKey: pair.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections.single.reason, 'key-substitution');
      expect(outcome.rejections.single.devices, ['devA']);
    });

    test('a public vault (no users.json) accepts a device with a valid key', () async {
      final pair = await crypto.generateDeviceKeyPair();
      final authorizer = OpLogAuthorizer(registry: _FakeRegistry(users: null), trustStore: _FakeTrustStore());

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA', pubKey: pair.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted.containsKey('devA'), isTrue);
      expect(outcome.rejections, isEmpty);
    });

    test('an all-legacy file (no pubKey) is accepted during migration (§8.1)', () async {
      final authorizer = OpLogAuthorizer(
        registry: _FakeRegistry(users: _users([_user('owner', owner: true), _user('alice')])),
        trustStore: _FakeTrustStore(),
      );

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA')], // no pubKey
        },
      );

      expect(outcome.accepted.containsKey('devA'), isTrue);
      expect(outcome.rejections, isEmpty);
    });
  });

  group('OpLogAuthorizer registry memoization (NOET-31 review: once per sync cycle) —', () {
    const vault = '/vault';
    const vaultId = 'vault-1';
    const relPath = 'pages/notes/ideas.md';
    OpLogSystem? oplogRef;

    test('the registry snapshot is loaded once and shared across buildDag calls of a cycle', () async {
      final a = await crypto.generateDeviceKeyPair();
      final b = await crypto.generateDeviceKeyPair();
      final users = _users([_user('owner', owner: true), _user('alice')]);
      final registry = _CountingRegistry(
        users: users,
        devices: {
          'alice': _devices('alice', [_device('devA', a.publicKeyBase64Url), _device('devB', b.publicKeyBase64Url)]),
        },
      );
      final fs = _FakeFs();
      final local = await crypto.generateDeviceKeyPair();
      final keyStore = FakeSecureKeyStore();
      await keyStore.storeDevicePrivateKey(vaultId, local.privateKeyBase64Url);
      final deviceService = FakeDeviceService()
        ..setDevice(DeviceIdentity(uuid: 'local-device', name: 'Local', createdAt: DateTime(2026), lastHlc: null, publicKey: local.publicKeyBase64Url));
      final vaultSystem = createTestVaultSystem(fileSystem: fs, deviceService: deviceService);
      final hlcService = HlcService(vaultSystem, deviceService);
      addTearDown(() {
        oplogRef?.dispose();
        oplogRef = null;
        vaultSystem.dispose();
      });

      final authorizer = OpLogAuthorizer(registry: registry, trustStore: _FakeTrustStore());
      final oplog = OpLogSystem(
        fileSystem: fs,
        hlcService: hlcService,
        vaultSystem: vaultSystem,
        deviceService: deviceService,
        crypto: crypto,
        secureKeyStore: keyStore,
        authorizer: authorizer,
      );
      vaultSystem.currentVault.value = VaultEntity(id: vaultId, name: 'V', rootPath: '/vault', createdAt: DateTime(2026));
      oplogRef = oplog;

      Future<void> writeFile(String deviceId, ({String publicKeyBase64Url, String privateKeyBase64Url}) key, Hlc hlc) async {
        await keyStore.storeDevicePrivateKey('vault-$deviceId', key.privateKeyBase64Url);
        final signer = OpLogSigner(crypto: crypto, secureKeyStore: keyStore, serializer: const OpLogSerializer());
        final signed = await signer.sign(
          _entry(hlc: hlc, device: deviceId),
          relPath,
          vaultId: 'vault-$deviceId',
          devicePublicKeyBase64Url: key.publicKeyBase64Url,
        );
        const dir = '/vault/.sync/$relPath';
        if (!fs.dirs.contains(dir)) fs.dirs.add(dir);
        await fs.appendToFile('$dir/$deviceId.oplog.jsonl', '${const OpLogSerializer().encode(signed)}\n');
      }

      await writeFile('devA', a, _h(100, 'devA'));
      await writeFile('devB', b, _h(200, 'devB'));

      // One sync cycle: the snapshot is prepared ONCE, then shared by every
      // buildDag call of the cycle (mirrors SyncSystem.checkAll).
      final snapshot = await oplog.prepareVerification();
      expect(snapshot, isNotNull, reason: 'the gate is installed and the vault is active');
      expect(registry.loadUserRegistryCalls, 1);
      expect(registry.loadDeviceRegistryCalls, 2, reason: 'one device file per user in users.json (owner + alice)');

      final dagA = await oplog.buildDag(relPath, verification: snapshot);
      final dagB = await oplog.buildDag(relPath, verification: snapshot);

      // No extra registry reads happened for the second (or first) file:
      // the expensive read+verify pass ran exactly once for the whole cycle.
      expect(registry.loadUserRegistryCalls, 1, reason: 'the shared snapshot must not re-read users.json per file');
      expect(registry.loadDeviceRegistryCalls, 2, reason: 'the shared snapshot must not re-read device files per file');
      expect(dagA.topology, DagTopology.diverged);
      expect(dagB.topology, DagTopology.diverged);
    });

    test('a gate failure to read the TOFU store is reported as trust-store-error, not key-substitution', () async {
      final pair = await crypto.generateDeviceKeyPair();
      final registry = _FakeRegistry(
        users: _users([_user('owner', owner: true), _user('alice')]),
        devices: {
          'alice': _devices('alice', [_device('devA', pair.publicKeyBase64Url)]),
        },
      );
      final authorizer = OpLogAuthorizer(registry: registry, trustStore: _FakeTrustStore(throwOnObserve: true));

      final outcome = await authorizer.authorize(
        vaultRootPath: vault,
        relativePath: relPath,
        entriesByDevice: {
          'devA': [_entry(hlc: _h(100, 'a'), device: 'devA', pubKey: pair.publicKeyBase64Url)],
        },
      );

      expect(outcome.accepted, isEmpty, reason: 'a device whose key cannot be TOFU-verified is rejected (§8.4)');
      expect(outcome.rejections.single.reason, 'trust-store-error');
    });
  });

  group('OpLogSystem.buildDag verification gate (full chain: NOET-28 → TOFU → cert → registry)', () {
    late _FakeFs fs;
    late VaultSystem vaultSystem;
    late FakeDeviceService deviceService;
    late HlcService hlcService;
    late FakeSecureKeyStore keyStore;
    OpLogSystem? oplogRef;
    const vaultId = 'vault-1';
    const relPath = 'pages/notes/ideas.md';

    setUp(() async {
      fs = _FakeFs();
      final local = await crypto.generateDeviceKeyPair();
      keyStore = FakeSecureKeyStore();
      await keyStore.storeDevicePrivateKey(vaultId, local.privateKeyBase64Url);
      deviceService = FakeDeviceService()
        ..setDevice(DeviceIdentity(uuid: 'local-device', name: 'Local', createdAt: DateTime(2026), lastHlc: null, publicKey: local.publicKeyBase64Url));
      vaultSystem = createTestVaultSystem(fileSystem: fs, deviceService: deviceService);
      hlcService = HlcService(vaultSystem, deviceService);
    });

    tearDown(() {
      oplogRef?.dispose();
      oplogRef = null;
      vaultSystem.dispose();
    });

    /// Writes a real signed single-entry oplog file for [deviceId] (pubKey on
    /// the first entry, signature by [privKey]) using the NOET-28 signer.
    Future<void> writeSignedFile({required String deviceId, required String pubKey, required String privKey, required Hlc hlc}) async {
      await keyStore.storeDevicePrivateKey('vault-$deviceId', privKey);
      final signer = OpLogSigner(crypto: crypto, secureKeyStore: keyStore, serializer: const OpLogSerializer());
      final signed = await signer.sign(
        _entry(hlc: hlc, device: deviceId),
        relPath,
        vaultId: 'vault-$deviceId',
        devicePublicKeyBase64Url: pubKey,
      );
      const dir = '/vault/.sync/$relPath';
      if (!fs.dirs.contains(dir)) fs.dirs.add(dir);
      await fs.appendToFile('$dir/$deviceId.oplog.jsonl', '${const OpLogSerializer().encode(signed)}\n');
    }

    OpLogSystem buildOpLog({required UserRegistry? users, required Map<String, DeviceRegistry> devices, required ITrustStore trustStore}) {
      final authorizer = OpLogAuthorizer(
        registry: _FakeRegistry(users: users, devices: devices),
        trustStore: trustStore,
      );
      // Construct FIRST so the system registers its vault listener, then set the
      // value to activate the reader (mirrors oplog_system_test.dart).
      final oplog = OpLogSystem(
        fileSystem: fs,
        hlcService: hlcService,
        vaultSystem: vaultSystem,
        deviceService: deviceService,
        crypto: crypto,
        secureKeyStore: keyStore,
        authorizer: authorizer,
      );
      vaultSystem.currentVault.value = VaultEntity(id: vaultId, name: 'V', rootPath: '/vault', createdAt: DateTime(2026));
      oplogRef = oplog;
      return oplog;
    }

    test('a valid multi-device, single-user DAG merges as before (no regression)', () async {
      final a = await crypto.generateDeviceKeyPair();
      final b = await crypto.generateDeviceKeyPair();
      final users = _users([_user('owner', owner: true), _user('alice')]);
      final registry = {
        'alice': _devices('alice', [_device('devA', a.publicKeyBase64Url), _device('devB', b.publicKeyBase64Url)]),
      };

      await writeSignedFile(deviceId: 'devA', pubKey: a.publicKeyBase64Url, privKey: a.privateKeyBase64Url, hlc: _h(100, 'devA'));
      await writeSignedFile(deviceId: 'devB', pubKey: b.publicKeyBase64Url, privKey: b.privateKeyBase64Url, hlc: _h(200, 'devB'));

      final oplog = buildOpLog(users: users, devices: registry, trustStore: TrustStoreImpl(fs));
      final dag = await oplog.buildDag(relPath);

      expect(dag.topology, DagTopology.diverged, reason: 'two devices, divergent heads');
      expect(dag.entriesByHlc.keys, hasLength(2));
      expect(dag.heads.keys, {'devA', 'devB'}, reason: 'both authorized devices contribute heads');
    });

    test('a forged device (published key not bound in the registry) is excluded from the DAG', () async {
      final victim = await crypto.generateDeviceKeyPair();
      final attacker = await crypto.generateDeviceKeyPair();
      final users = _users([_user('owner', owner: true), _user('alice')]);
      // The registry binds 'victim' to the victim's key — NOT the attacker's.
      final registry = {
        'alice': _devices('alice', [_device('victim', victim.publicKeyBase64Url)]),
      };

      // The attacker publishes their own key and signs their own entry; the
      // NOET-28 verifier accepts it (valid under the published key), but the
      // gate's certificate check finds no binding for that key → rejected.
      await writeSignedFile(deviceId: 'victim', pubKey: attacker.publicKeyBase64Url, privKey: attacker.privateKeyBase64Url, hlc: _h(100, 'victim'));

      final oplog = buildOpLog(users: users, devices: registry, trustStore: TrustStoreImpl(fs));
      final dag = await oplog.buildDag(relPath);

      expect(dag.topology, DagTopology.empty, reason: 'the forged (unbound) device contributes nothing to the DAG');
      expect(dag.entriesByHlc, isEmpty);
    });

    test('a key-substitution (TOFU mismatch) device is excluded from the DAG', () async {
      final original = await crypto.generateDeviceKeyPair();
      final newPair = await crypto.generateDeviceKeyPair();
      final users = _users([_user('owner', owner: true), _user('alice')]);
      // The registry binds 'devA' to the ORIGINAL key.
      final registry = {
        'alice': _devices('alice', [_device('devA', original.publicKeyBase64Url)]),
      };

      // The file now publishes the NEW key (a rekey/substitution) and is
      // signed with it, so NOET-28 accepts it; the gate then detects the
      // mismatch against the pre-pinned original key.
      await writeSignedFile(deviceId: 'devA', pubKey: newPair.publicKeyBase64Url, privKey: newPair.privateKeyBase64Url, hlc: _h(100, 'devA'));

      final trust = TrustStoreImpl(fs);
      await trust.observeKey('/vault', 'devA', original.publicKeyBase64Url); // pin the original

      final oplog = buildOpLog(users: users, devices: registry, trustStore: trust);
      final dag = await oplog.buildDag(relPath);

      expect(dag.topology, DagTopology.empty, reason: 'a key-substituted device must not merge (§5.2 rule 3)');
      expect(dag.entriesByHlc, isEmpty);
    });

    test('a valid device in an otherwise-forced vault still merges (only foreign entries are dropped)', () async {
      final a = await crypto.generateDeviceKeyPair();
      final attacker = await crypto.generateDeviceKeyPair();
      final users = _users([_user('owner', owner: true), _user('alice')]);
      final registry = {
        'alice': _devices('alice', [_device('devA', a.publicKeyBase64Url)]),
      };

      await writeSignedFile(deviceId: 'devA', pubKey: a.publicKeyBase64Url, privKey: a.privateKeyBase64Url, hlc: _h(100, 'devA'));
      // A forged entry from an unbound device is also present.
      await writeSignedFile(deviceId: 'attacker', pubKey: attacker.publicKeyBase64Url, privKey: attacker.privateKeyBase64Url, hlc: _h(300, 'attacker'));

      final oplog = buildOpLog(users: users, devices: registry, trustStore: TrustStoreImpl(fs));
      final dag = await oplog.buildDag(relPath);

      expect(dag.topology, DagTopology.single, reason: 'only the authorized device remains → a single head');
      expect(dag.entriesByHlc.keys, hasLength(1));
      expect(dag.heads.keys, {'devA'});
    });
  });
}
