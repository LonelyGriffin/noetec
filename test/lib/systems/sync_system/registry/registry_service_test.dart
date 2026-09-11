// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/user/user_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_signing.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../../../helpers/test_fakes.dart';

/// A [FakeFileSystemService] with a working [IFileSystemService.renameFileOrDirectory]
/// (the shared fake no-ops the rename; the registry service's atomic write
/// relies on it moving the content to the canonical name).
class _FakeFs extends FakeFileSystemService {
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final content = files.remove(oldPath);
    if (content != null) files[newPath] = content;
  }

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
}

Hlc _h(int ms) => Hlc(physicalMs: ms, counter: 0, deviceId: 'aaaaaaaa');

void main() {
  late CryptoServiceImpl crypto;
  late RegistrySigning signing;
  late String ownerPriv;
  late String ownerPub;

  setUp(() async {
    crypto = CryptoServiceImpl();
    signing = RegistrySigning(crypto);
    final owner = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xA0 + i));
    ownerPriv = owner.privateKeyBase64Url;
    ownerPub = owner.publicKeyBase64Url;
  });

  UserRegistry userFile({required Hlc rev, required List<UserRecord> users}) {
    final unsigned = UserRegistry(version: 1, revision: rev, parent: null, ownerUserId: 'o', users: users, signature: '');
    return unsigned; // signed by the helpers below
  }

  Future<UserRegistry> signUsers(UserRegistry file, {List<UserRecord>? users}) async {
    final records = users ?? file.users;
    final signedUsers = <UserRecord>[];
    for (final u in records) {
      signedUsers.add(await signing.signUserRecord(u, ownerPriv)); // v1: owner signs every record
    }
    return signing.signUserFileOnly(
      UserRegistry(version: file.version, revision: file.revision, parent: file.parent, ownerUserId: file.ownerUserId, users: signedUsers, signature: ''),
      ownerPrivateKey: ownerPriv,
    );
  }

  UserRecord u(String id, {Hlc? updatedAt, String? name}) => UserRecord(
    userId: id,
    name: name ?? 'n-$id',
    publicKey: id == 'o' ? ownerPub : 'pk-$id',
    role: id == 'o' ? 'owner' : 'member',
    addedBy: 'o',
    updatedAt: updatedAt ?? _h(100),
    removedAt: null,
    signature: '',
  );

  Future<({RegistryServiceImpl service, _FakeFs fs, VaultSystem vault})> buildService({String root = '/vault', UserIdentity? identity, String? identityPrivKey}) async {
    final fs = _FakeFs();
    final deviceService = FakeDeviceService();
    deviceService.setDevice(DeviceIdentity(uuid: 'test-device-uuid', name: 'Test Device', createdAt: DateTime.now(), lastHlc: null, publicKey: 'test-public-key'));
    final vault = createTestVaultSystem(fileSystem: fs, deviceService: deviceService);
    final keyStore = FakeSecureKeyStore();
    if (identityPrivKey != null) await keyStore.storeIdentityPrivateKey('v1', identityPrivKey);
    final hlcService = HlcService(vault, deviceService);
    final service = RegistryServiceImpl(
      fileSystem: fs,
      hlcService: hlcService,
      crypto: crypto,
      secureKeyStore: keyStore,
      vaultSystem: vault,
      identitySource: identity == null ? null : _FixedIdentitySource(identity),
    );
    vault.currentVault.value = VaultEntity(id: 'v1', name: 'Vault', rootPath: '/vault', createdAt: DateTime(2026));
    return (service: service, fs: fs, vault: vault);
  }

  void writeUsers(_FakeFs fs, String fileName, UserRegistry file) {
    fs.files['/vault/.sync/$fileName'] = jsonEncode(file.toWireMap());
    fs.dirs.add('/vault/.sync');
  }

  UserIdentity ownerIdentity() => UserIdentity(userId: 'o', name: 'Owner', publicKey: ownerPub, role: 'owner');

  group('reconcileUserRegistry —', () {
    test('fast-path: a single candidate at a conflicted name is renamed to canonical', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      final file = await signUsers(userFile(rev: _h(1000), users: [u('o')]));
      writeUsers(b.fs, 'users (conflicted copy 1).json', file); // NOT canonical

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'fast-path');
      expect(report.merged, isTrue); // the conflicted copy was renamed to canonical
      expect(b.fs.files.containsKey('/vault/.sync/users.json'), isTrue);
      expect(b.fs.files.containsKey('/vault/.sync/users (conflicted copy 1).json'), isFalse);

      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById['o'], isNotNull);
    });

    test('fast-path: a candidate already at the canonical name is left in place', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      final file = await signUsers(userFile(rev: _h(1000), users: [u('o')]));
      writeUsers(b.fs, 'users.json', file); // already canonical

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'fast-path');
      expect(report.merged, isFalse); // no rename needed
      expect(b.fs.files.containsKey('/vault/.sync/users.json'), isTrue);
    });

    test('three-way: two diverged candidates of one owner merge per record', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      // ours: edits record "a"; theirs: edits record "b" (a different record).
      final ours = await signUsers(
        userFile(
          rev: _h(1000),
          users: [
            u('o'),
            u('a', updatedAt: _h(2000), name: 'a-edited'),
            u('b', updatedAt: _h(1000)),
          ],
        ),
        users: [
          u('o'),
          u('a', updatedAt: _h(2000), name: 'a-edited'),
          u('b', updatedAt: _h(1000)),
        ],
      );
      final theirs = await signUsers(
        userFile(
          rev: _h(1500),
          users: [
            u('o'),
            u('a', updatedAt: _h(1000)),
            u('b', updatedAt: _h(3000), name: 'b-edited'),
          ],
        ),
        users: [
          u('o'),
          u('a', updatedAt: _h(1000)),
          u('b', updatedAt: _h(3000), name: 'b-edited'),
        ],
      );
      writeUsers(b.fs, 'users.json', theirs); // canonical slot
      writeUsers(b.fs, 'users (conflicted copy 1).json', ours);

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'three-way');
      expect(report.merged, isTrue);
      // The conflicted copy is removed after the commit.
      expect(b.fs.files.containsKey('/vault/.sync/users (conflicted copy 1).json'), isFalse);
      // The merged file carries BOTH edits (no loss).
      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById['a']!.name, 'a-edited');
      expect(loaded.usersById['b']!.name, 'b-edited');
    });

    test('file-level LWW fallback: diverged owners keep the larger revision', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      // Two different owners → no common ancestor.
      final low = await signUsers(userFile(rev: _h(1000), users: [u('o')]));
      final zz = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xC0 + i));
      // The owner record carries the signer's REAL public key so the whole-file
      // signature (under zz's key) resolves and verifies.
      final high = UserRegistry(
        version: 1,
        revision: _h(2000),
        parent: null,
        ownerUserId: 'zz',
        users: [UserRecord(userId: 'zz', name: 'z', publicKey: zz.publicKeyBase64Url, role: 'owner', addedBy: 'zz', updatedAt: _h(1900), removedAt: null, signature: '')],
        signature: '',
      );
      final highSigned = await signing.signUserRegistry(high, ownerPrivateKey: zz.privateKeyBase64Url, recordKeys: {'zz': zz.privateKeyBase64Url});
      writeUsers(b.fs, 'users.json', low);
      writeUsers(b.fs, 'users (conflicted copy 1).json', highSigned);

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'lww-fallback');
      expect(report.droppedFiles, isNotEmpty);
      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.ownerUserId, 'zz'); // the larger revision won
    });

    test('a merge cannot be committed when the local user is not the owner', () async {
      // The operator is a plain member (not the owner "o").
      final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
      final b = await buildService(
        identity: UserIdentity(userId: 'm', name: 'Member', publicKey: member.publicKeyBase64Url, role: 'member'),
        identityPrivKey: member.privateKeyBase64Url,
      );
      final ours = await signUsers(
        userFile(
          rev: _h(1000),
          users: [
            u('o'),
            u('a', updatedAt: _h(2000), name: 'x'),
          ],
        ),
        users: [
          u('o'),
          u('a', updatedAt: _h(2000), name: 'x'),
        ],
      );
      final theirs = await signUsers(
        userFile(
          rev: _h(1500),
          users: [
            u('o'),
            u('a', updatedAt: _h(3000), name: 'y'),
          ],
        ),
        users: [
          u('o'),
          u('a', updatedAt: _h(3000), name: 'y'),
        ],
      );
      writeUsers(b.fs, 'users.json', ours);
      writeUsers(b.fs, 'users (conflicted copy 1).json', theirs);

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'three-way');
      expect(report.merged, isFalse);
      expect(report.note, contains('not the owner'));
      // The merge was NOT committed: the canonical file still holds the
      // original candidate (record "a" = "x", ours), not the merge winner ("y").
      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById['a']!.name, 'x');
    });

    test('no candidates: noop, nothing is written', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'noop');
      expect(b.fs.files.containsKey('/vault/.sync/users.json'), isFalse);
    });

    test('an unparseable candidate is rejected and reported', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      final good = await signUsers(userFile(rev: _h(1000), users: [u('o')]));
      writeUsers(b.fs, 'users.json', good);
      b.fs.files['/vault/.sync/users (conflicted copy 1).json'] = '{not json';

      final report = await b.service.reconcileUserRegistry();
      expect(report.mode, 'fast-path');
      expect(report.rejectedFiles, contains('/vault/.sync/users (conflicted copy 1).json'));
    });
  });

  group('reconcileDeviceRegistry —', () {
    test('two devices of one user merge per record (acceptance: same-user race)', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      DeviceRegistry devFile({required Hlc rev, required List<DeviceRecord> devices}) =>
          DeviceRegistry(version: 1, revision: rev, parent: null, userId: 'o', devices: devices, signature: '');
      Future<DeviceRegistry> signDev(DeviceRegistry f) async {
        final signedDevices = <DeviceRecord>[];
        for (final d in f.devices) {
          signedDevices.add(await signing.signDeviceRecord(d, ownerPriv));
        }
        return signing.signDeviceFileOnly(
          DeviceRegistry(version: f.version, revision: f.revision, parent: f.parent, userId: f.userId, devices: signedDevices, signature: ''),
          userPrivateKey: ownerPriv,
        );
      }

      final d1 = DeviceRecord(deviceUuid: 'd1', devicePublicKey: 'pk-d1', userId: 'o', deviceName: 'dev1', issuedAt: _h(90), updatedAt: _h(100), removedAt: null, signature: '');
      final d2 = DeviceRecord(deviceUuid: 'd2', devicePublicKey: 'pk-d2', userId: 'o', deviceName: 'dev2', issuedAt: _h(90), updatedAt: _h(300), removedAt: null, signature: '');
      final devA = await signDev(devFile(rev: _h(1000), devices: [d1, d2]));
      final devB = await signDev(
        devFile(
          rev: _h(1500),
          devices: [
            DeviceRecord(deviceUuid: 'd1', devicePublicKey: 'pk-d1', userId: 'o', deviceName: 'renamed', issuedAt: _h(90), updatedAt: _h(200), removedAt: null, signature: ''),
          ],
        ),
      );
      b.fs.files['/vault/.sync/devices/o.json'] = jsonEncode(devB.toWireMap());
      b.fs.files['/vault/.sync/devices/o (conflicted copy 1).json'] = jsonEncode(devA.toWireMap());
      b.fs.dirs.add('/vault/.sync/devices');

      final report = await b.service.reconcileDeviceRegistry('o');
      expect(report.mode, 'three-way');
      expect(report.merged, isTrue);
      final loaded = await b.service.loadDeviceRegistry('o');
      expect(loaded, isNotNull);
      expect(loaded!.devicesById['d1']!.deviceName, 'renamed'); // d1: newer edit wins
      expect(loaded.devicesById['d2']!.updatedAt, _h(300)); // d2: only on device A
    });
  });

  group('operations (§3.6) —', () {
    test('addUser bootstraps users.json, then adds a member', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      // Bootstrap: no canonical file → the operator becomes the owner.
      await b.service.addUser(userId: 'o', name: 'Owner', publicKey: ownerPub, role: 'owner');
      expect(b.fs.files.containsKey('/vault/.sync/users.json'), isTrue);
      // Add a member (a fresh key).
      final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
      final withMember = await b.service.addUser(userId: 'm', name: 'Member', publicKey: member.publicKeyBase64Url);
      expect(withMember.usersById['o'], isNotNull);
      expect(withMember.usersById['m']!.publicKey, member.publicKeyBase64Url);

      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById['m'], isNotNull);
    });

    test('revokeUser tombstones the record', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      await b.service.addUser(userId: 'o', name: 'Owner', publicKey: ownerPub, role: 'owner');
      final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
      await b.service.addUser(userId: 'm', name: 'Member', publicKey: member.publicKeyBase64Url);

      final revoked = await b.service.revokeUser('m');
      expect(revoked.usersById['m']!.removedAt, isNotNull);
      expect(revoked.usersById['o']!.removedAt, isNull);

      final loaded = await b.service.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById['m']!.removedAt, isNotNull);
    });

    test('addDevice creates the operator device file; revokeDevice tombstones', () async {
      final b = await buildService(identity: ownerIdentity(), identityPrivKey: ownerPriv);
      final added = await b.service.addDevice(deviceUuid: 'd1', devicePublicKey: 'pk-d1', deviceName: 'Dev 1');
      expect(added.devicesById['d1'], isNotNull);
      expect(b.fs.files.containsKey('/vault/.sync/devices/o.json'), isTrue);

      final revoked = await b.service.revokeDevice('d1');
      expect(revoked.devicesById['d1']!.removedAt, isNotNull);

      final loaded = await b.service.loadDeviceRegistry('o');
      expect(loaded, isNotNull);
      expect(loaded!.devicesById['d1']!.removedAt, isNotNull);
    });
  });
}

/// A fixed [IIdentitySource] for tests: returns one identity (and no
/// last-verified registry, so the key provider falls back to the file's own
/// owner record).
class _FixedIdentitySource implements IIdentitySource {
  _FixedIdentitySource(this._identity);

  final UserIdentity _identity;

  @override
  Future<({UserIdentity identity, UserRegistry? lastVerified})> resolve(String vaultRootPath) async => (identity: _identity, lastVerified: null);
}
