// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/service/trust_store.dart';
import 'package:noetec/service/user_service.dart';
import 'package:noetec/systems/oplog_system/oplog_authorizer.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_signing.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../helpers/test_fakes.dart';

/// A [FakeFileSystemService] with a working rename (the registry service's
/// atomic write relies on `.tmp` → canonical renames).
class _OnboardFs extends FakeFileSystemService {
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final content = files.remove(oldPath);
    if (content != null) files[newPath] = content;
    if (dirs.remove(oldPath)) dirs.add(newPath);
  }
}

/// A [IDeviceService] that behaves like [DeviceServiceImpl] (reads
/// `device.json`, generates a key pair + device on first use). Each instance
/// gets a unique device UUID (first 8 chars stable, so `truncatedDeviceId`
/// works — HLC keys embed its first 8 chars, entity/hlc.dart), and key-pair
/// generations are counted so tests can assert "a first device is generated".
class _RecordingDeviceService implements IDeviceService {
  _RecordingDeviceService(this._fileSystem, this._crypto, this._keyStore) {
    _instanceCounter++;
    final suffix = _instanceCounter.toString().padLeft(12, '0');
    _device = DeviceIdentity(uuid: 'aaaaaaaa-bbbb-cccc-dddd-$suffix', name: 'Test Device', createdAt: DateTime(2026), lastHlc: null, publicKey: null);
  }

  static int _instanceCounter = 0;

  final IFileSystemService _fileSystem;
  final ICryptoService _crypto;
  final ISecureKeyStore _keyStore;

  int keyPairGenerations = 0;
  late DeviceIdentity _device;

  /// Drops the in-memory device, simulating a machine that does not have this
  /// device yet (`ensureDevice` will regenerate its key pair on next use).
  void reset() => _device = DeviceIdentity(uuid: _device.uuid, name: _device.name, createdAt: _device.createdAt, lastHlc: null, publicKey: null);

  @override
  DeviceIdentity? get currentDevice => _device;

  @override
  Future<DeviceIdentity> ensureDevice(String vaultRootPath, String vaultId) async {
    final devicePath = '$vaultRootPath/.noetec/device.json';
    if (await _fileSystem.fileExists(devicePath)) {
      final content = await _fileSystem.readFile(devicePath);
      _device = DeviceIdentity.fromJson(jsonDecode(content) as Map<String, dynamic>);
      return _device;
    }
    final keyPair = await _crypto.generateDeviceKeyPair();
    keyPairGenerations++;
    _device = DeviceIdentity(uuid: _device.uuid, name: _device.name, createdAt: _device.createdAt, lastHlc: null, publicKey: keyPair.publicKeyBase64Url);
    if (!await _fileSystem.directoryExists('$vaultRootPath/.noetec')) {
      await _fileSystem.createDirectory('$vaultRootPath/.noetec');
    }
    await _fileSystem.writeFile(devicePath, jsonEncode(_device.toJson()));
    await _keyStore.storeDevicePrivateKey(vaultId, keyPair.privateKeyBase64Url);
    return _device;
  }

  @override
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey) async {
    if (_device.publicKey == null) return; // never initialized for this vault
    _device = _device.withLastHlc(hlcKey);
  }

  @override
  void clear() {}
}

/// One in-memory "device" running the real onboarding stack (real
/// [UserServiceImpl], [RegistryServiceImpl], [CryptoServiceImpl]) against an
/// in-memory vault. [root]/[vaultId] match the real layout: the same vault id
/// is seen by every device of the vault, the secure key store is per-device.
class _OnboardHarness {
  _OnboardHarness({
    required this.fs,
    required this.keyStore,
    required this.deviceService,
    required this.userService,
    required this.registry,
    required this.vault,
    required this.onboarding,
    required this.signing,
    required this.authorizer,
  });

  final _OnboardFs fs;
  final FakeSecureKeyStore keyStore;
  final _RecordingDeviceService deviceService;
  final UserServiceImpl userService;
  final RegistryServiceImpl registry;
  final VaultSystem vault;
  final OnboardingServiceImpl onboarding;
  final RegistrySigning signing;
  final OpLogAuthorizer authorizer;
}

Future<_OnboardHarness> _buildHarness({required CryptoServiceImpl crypto, required RegistrySigning signing, String root = '/vault', String vaultId = 'v1'}) async {
  final fs = _OnboardFs();
  final keyStore = FakeSecureKeyStore();
  final idService = FakeIdService();
  final deviceService = _RecordingDeviceService(fs, crypto, keyStore);
  final userService = UserServiceImpl(fs, idService, crypto, keyStore);
  final vault = VaultSystem(fs, FakeVaultRepository(), idService, deviceService);
  final hlcService = HlcService(vault, deviceService);
  final registry = RegistryServiceImpl(fileSystem: fs, hlcService: hlcService, crypto: crypto, secureKeyStore: keyStore, vaultSystem: vault);
  final onboarding = OnboardingServiceImpl(
    fileSystem: fs,
    deviceService: deviceService,
    userService: userService,
    registry: registry,
    crypto: crypto,
    idService: idService,
    vaultSystem: vault,
  );
  final authorizer = OpLogAuthorizer(registry: registry, trustStore: TrustStoreImpl(fs));

  // "Open" the vault the way VaultSystem does: the device is guaranteed
  // before currentVault is set (HlcService's listener needs it).
  await deviceService.ensureDevice(root, vaultId);
  vault.currentVault.value = VaultEntity(id: vaultId, name: 'Vault', rootPath: root, createdAt: DateTime(2026));
  _vaultsToDispose.add(vault);

  return _OnboardHarness(
    fs: fs,
    keyStore: keyStore,
    deviceService: deviceService,
    userService: userService,
    registry: registry,
    vault: vault,
    onboarding: onboarding,
    signing: signing,
    authorizer: authorizer,
  );
}

/// Writes a device registry for [userId] signed with [userPrivKey] (the
/// "other device" of a user, created outside the onboarding service).
Future<DeviceRegistry> _writeForeignDeviceFile(
  _OnboardHarness h, {
  required String userId,
  required String userPrivKey,
  required String deviceUuid,
  required String devicePub,
  String deviceName = 'foreign device',
}) async {
  const deviceId = 'cccccccc';
  final issued = Hlc.now(null, deviceId);
  final record = DeviceRecord(
    deviceUuid: deviceUuid,
    devicePublicKey: devicePub,
    userId: userId,
    deviceName: deviceName,
    issuedAt: issued,
    updatedAt: issued,
    removedAt: null,
    signature: '',
  );
  final signedRecord = await h.signing.signDeviceRecord(record, userPrivKey);
  final unsigned = DeviceRegistry(version: 1, revision: Hlc.now(null, deviceId), parent: null, userId: userId, devices: [signedRecord], signature: '');
  final signed = await h.signing.signDeviceFileOnly(unsigned, userPrivateKey: userPrivKey);
  h.fs.dirs.add('/vault/.sync/devices');
  h.fs.files['/vault/.sync/devices/$userId.json'] = jsonEncode(signed.toWireMap());
  return signed;
}

/// Runs the attribution/authorization chain (sync-security.md §3.5, §7) for a
/// single entry authored by [deviceUuid] under [observedKey].
Future<AuthorizationOutcome> _runChain(_OnboardHarness h, {required String deviceUuid, required String? observedKey}) async {
  final entry = OpLogEntry(
    version: 1,
    hlc: Hlc.now(null, 'dddddddd'),
    parent: null,
    parentB: null,
    type: OpEntryType.save,
    blockOps: null,
    fileOp: null,
    fileHash: null,
    deviceId: deviceUuid,
    pubKey: observedKey,
  );
  final snapshot = await h.authorizer.loadSnapshot();
  return h.authorizer.authorize(
    vaultRootPath: '/vault',
    relativePath: 'pages/note',
    entriesByDevice: {
      deviceUuid: [entry],
    },
    snapshot: snapshot,
  );
}

String _memberMnemonic(Iterable<int> seed) {
  final hex = seed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return bip39.entropyToMnemonic(hex);
}

/// Every [VaultSystem] created this run, disposed exactly once in tearDown
/// (a test that builds its own stack without touching the shared harness
/// still gets cleaned up, and no vault is disposed twice).
final _vaultsToDispose = <VaultSystem>[];

void main() {
  late CryptoServiceImpl crypto;
  late RegistrySigning signing;
  late _OnboardHarness h;

  setUp(() async {
    crypto = CryptoServiceImpl();
    signing = RegistrySigning(crypto);
  });

  tearDown(() {
    for (final vault in _vaultsToDispose) {
      vault.dispose();
    }
    _vaultsToDispose.clear();
  });

  group('createVaultOnboarding —', () {
    test('creates a valid owner + first device with a back-up-able seed', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final result = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      // The seed is a 24-word BIP39 mnemonic (back-up-able, ADR-0007 §2).
      expect(result.mnemonic.split(' ').length, 24);
      expect(bip39.validateMnemonic(result.mnemonic), isTrue);

      // Owner record: self-signed, role owner, administers users.json.
      expect(result.owner.userId, result.userRegistry.ownerUserId);
      final ownerRecord = result.userRegistry.usersById[result.owner.userId];
      expect(ownerRecord, isNotNull);
      expect(ownerRecord!.role, 'owner');
      expect(ownerRecord.addedBy, result.owner.userId);
      expect(ownerRecord.publicKey, result.owner.publicKey);
      expect(ownerRecord.isRemoved, isFalse);

      // First device: certificate in devices/<ownerId>.json.
      expect(result.deviceRegistry.userId, result.owner.userId);
      expect(result.deviceRegistry.devices, hasLength(1));
      final cert = result.deviceRegistry.devices.single;
      expect(cert.deviceUuid, result.device.uuid);
      expect(cert.deviceName, 'Test Device');
      expect(cert.userId, result.owner.userId);
      expect(cert.isRemoved, isFalse);
      expect(cert.issuedAt, isNotNull);

      // A first device key pair was actually generated.
      expect(h.deviceService.keyPairGenerations, 1);

      // Secret hygiene: the identity seed + identity key live in secure
      // storage; identity.json carries only public fields.
      expect(await h.keyStore.hasIdentitySeed('v1'), isTrue);
      expect(await h.keyStore.readIdentityPrivateKey('v1'), isNotNull);
      final identityJson = jsonDecode(h.fs.files['/vault/.noetec/identity.json']!) as Map<String, dynamic>;
      expect(identityJson.keys.toSet(), {'userId', 'name', 'publicKey', 'role'});
    });

    test('writes spec-shaped users.json and devices/<ownerId>.json', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final result = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      final usersWire = jsonDecode(h.fs.files['/vault/.sync/users.json']!) as Map<String, dynamic>;
      expect(usersWire.keys.toSet(), {'version', 'revision', 'parent', 'owner_user_id', 'users', 'signature'});
      expect(usersWire['version'], 1);
      final userRecord = (usersWire['users'] as List).single as Map<String, dynamic>;
      expect(userRecord.keys.toSet(), {'userId', 'name', 'publicKey', 'role', 'addedBy', 'updatedAt', 'removedAt', 'signature'});

      final devicesWire = jsonDecode(h.fs.files['/vault/.sync/devices/${result.owner.userId}.json']!) as Map<String, dynamic>;
      expect(devicesWire.keys.toSet(), {'version', 'revision', 'parent', 'userId', 'devices', 'signature'});
      expect(devicesWire['version'], 1);
      final deviceRecord = (devicesWire['devices'] as List).single as Map<String, dynamic>;
      expect(deviceRecord.keys.toSet(), {'deviceUuid', 'devicePublicKey', 'userId', 'deviceName', 'issuedAt', 'updatedAt', 'removedAt', 'signature'});
    });

    test('the written registries verify through the registry service', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final result = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      // loadUserRegistry / loadDeviceRegistry reject any file whose
      // whole-file or per-record signature fails (§3.4).
      final users = await h.registry.loadUserRegistry();
      expect(users, isNotNull);
      expect(users!.ownerUserId, result.owner.userId);
      expect(users.usersById[result.owner.userId], isNotNull);

      final devices = await h.registry.loadDeviceRegistry(result.owner.userId);
      expect(devices, isNotNull);
      expect(devices!.devicesById[result.device.uuid], isNotNull);
      expect(devices.devicesById[result.device.uuid]!.devicePublicKey, result.device.publicKey);
    });

    test('creates .sync/devices/ when the vault has only .sync/pages/', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      h.fs.dirs.remove('/vault/.sync/devices');
      h.fs.dirs.add('/vault/.sync');
      h.fs.dirs.add('/vault/.sync/pages');

      await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      expect(h.fs.dirs, contains('/vault/.sync'));
      expect(h.fs.dirs, contains('/vault/.sync/devices'));
    });

    test('throws when the vault already has an identity', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      await expectLater(h.onboarding.createVaultOnboarding(ownerName: 'Again'), throwsStateError);
    });

    test('the owner device is authorized by the attribution chain', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final result = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      final outcome = await _runChain(h, deviceUuid: result.device.uuid, observedKey: result.device.publicKey);
      expect(outcome.hasRejections, isFalse, reason: outcome.rejections.map((r) => r.toString()).join('; '));
      expect(outcome.accepted.keys.toSet(), {result.device.uuid});
    });
  });

  group('bootstrapOwnerIdentity —', () {
    test('the first opened user becomes the owner of an identity-less vault', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      expect(h.fs.files.containsKey('/vault/.noetec/identity.json'), isFalse);

      final result = await h.onboarding.bootstrapOwnerIdentity(ownerName: 'First User');

      expect(result.userRegistry.ownerUserId, result.owner.userId);
      expect(result.userRegistry.usersById[result.owner.userId]!.role, 'owner');
      expect(result.deviceRegistry.devices, hasLength(1));
      final users = await h.registry.loadUserRegistry();
      expect(users, isNotNull);
    });

    test('throws when users.json already exists (established owner)', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.bootstrapOwnerIdentity(ownerName: 'Owner');

      // Simulate a later open without the local identity (identity.json gone
      // but the registry present).
      h.fs.files.remove('/vault/.noetec/identity.json');
      h.userService.clear();
      await expectLater(h.onboarding.bootstrapOwnerIdentity(ownerName: 'Rival'), throwsStateError);
    });

    test('throws when the vault already has an identity', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.bootstrapOwnerIdentity(ownerName: 'Owner');

      await expectLater(h.onboarding.bootstrapOwnerIdentity(ownerName: 'Again'), throwsStateError);
    });
  });

  group('restoreFromSeed —', () {
    test('a fresh device yields the same identity and a working bound device', () async {
      // Device A: create the vault, note the mnemonic.
      final a = await _buildHarness(crypto: crypto, signing: signing);
      final created = await a.onboarding.createVaultOnboarding(ownerName: 'Owner');

      // Device B: the same vault (same vault id), the synced .sync/ files,
      // but NO local identity/device state.
      final b = await _buildHarness(crypto: crypto, signing: signing);
      b.fs.dirs.addAll({'/vault/.noetec', '/vault/.sync', '/vault/.sync/devices'});
      b.fs.files['/vault/.sync/users.json'] = a.fs.files['/vault/.sync/users.json']!;
      b.fs.files['/vault/.sync/devices/${created.owner.userId}.json'] = a.fs.files['/vault/.sync/devices/${created.owner.userId}.json']!;
      // A fresh machine: no identity, and no local device (its key pair is
      // generated by restoreFromSeed).
      b.deviceService.reset();
      b.fs.files.remove('/vault/.noetec/device.json');
      final generationsBefore = b.deviceService.keyPairGenerations;
      expect(b.fs.files.containsKey('/vault/.noetec/identity.json'), isFalse);

      final restored = await b.onboarding.restoreFromSeed(mnemonic: created.mnemonic);

      // Same identity: the public key is deterministic from the seed, and the
      // userId is resolved from the user's users.json record by public key.
      expect(restored.identity.publicKey, created.owner.publicKey);
      expect(restored.identity.userId, created.owner.userId);
      expect(restored.identity.role, 'owner');

      // The new device is bound: its certificate was appended to the file.
      expect(restored.deviceRegistry.userId, created.owner.userId);
      expect(restored.deviceRegistry.devices, hasLength(2));
      final newCert = restored.deviceRegistry.devicesById[restored.device.uuid];
      expect(newCert, isNotNull);
      expect(newCert!.devicePublicKey, restored.device.publicKey);
      expect(newCert.userId, created.owner.userId);
      expect(newCert.isRemoved, isFalse);
      // A new device key pair was generated (the restore binds a new device).
      expect(b.deviceService.keyPairGenerations, generationsBefore + 1);

      // The new device's certificate verifies under the user's identity key:
      // loadDeviceRegistry re-verifies the whole file (whole-file + every
      // per-record signature, §3.4) and it still passes.
      final loaded = await b.registry.loadDeviceRegistry(created.owner.userId);
      expect(loaded, isNotNull);
      expect(loaded!.devicesById[restored.device.uuid], isNotNull);
      expect(loaded.devicesById[created.device.uuid], isNotNull); // the original device survived
    });

    test('the restored identity signs: the bound device is authorized end-to-end', () async {
      final a = await _buildHarness(crypto: crypto, signing: signing);
      final created = await a.onboarding.createVaultOnboarding(ownerName: 'Owner');

      final b = await _buildHarness(crypto: crypto, signing: signing);
      b.fs.dirs.addAll({'/vault/.noetec', '/vault/.sync', '/vault/.sync/devices'});
      b.fs.files['/vault/.sync/users.json'] = a.fs.files['/vault/.sync/users.json']!;
      b.fs.files['/vault/.sync/devices/${created.owner.userId}.json'] = a.fs.files['/vault/.sync/devices/${created.owner.userId}.json']!;

      final restored = await b.onboarding.restoreFromSeed(mnemonic: created.mnemonic);

      // The restored device writes an entry: it passes TOFU, the certificate
      // check, and the registry filter (sync-security.md §3.5, §7).
      final outcome = await _runChain(b, deviceUuid: restored.device.uuid, observedKey: restored.device.publicKey);
      expect(outcome.hasRejections, isFalse, reason: outcome.rejections.map((r) => r.toString()).join('; '));
    });

    test('re-binding the same device keeps issuedAt and does not duplicate the record', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final created = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');
      final firstIssuedAt = created.deviceRegistry.devices.single.issuedAt;

      // A second restore (e.g. the user re-runs recovery on the same device).
      final again = await h.onboarding.restoreFromSeed(mnemonic: created.mnemonic);

      expect(again.deviceRegistry.devices, hasLength(1));
      final record = again.deviceRegistry.devices.single;
      expect(record.issuedAt, firstIssuedAt);
      expect(h.registry.loadDeviceRegistry(created.owner.userId), completes);
    });

    test('an invalid mnemonic throws before any state changes', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await expectLater(h.onboarding.restoreFromSeed(mnemonic: 'not a valid mnemonic at all'), throwsArgumentError);
      expect(h.fs.files.containsKey('/vault/.noetec/identity.json'), isFalse);
      expect(h.fs.files.containsKey('/vault/.noetec/device.json'), isTrue); // the harness device, unchanged
    });

    test('a seed that does not match the existing identity is rejected', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final created = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      // A different seed derives a different identity key.
      final otherMnemonic = _memberMnemonic(List.generate(32, (i) => 0xB0 + i));
      expect(otherMnemonic, isNot(created.mnemonic));

      await expectLater(h.onboarding.restoreFromSeed(mnemonic: otherMnemonic), throwsStateError);
      // The original identity is untouched (UserIdentity has no ==, so
      // compare by field).
      final after = await h.userService.loadIdentity('/vault');
      expect(after?.publicKey, created.owner.publicKey);
      expect(after?.userId, created.owner.userId);
    });

    test('without users.json the restored user gets a fresh userId', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final ownerMnemonic = _memberMnemonic(List.generate(32, (i) => 0x10 + i));

      // A vault with a device but no onboarding (no users.json).
      final restored = await h.onboarding.restoreFromSeed(mnemonic: ownerMnemonic);

      expect(restored.deviceRegistry.devices, hasLength(1));
      expect(restored.identity.userId, isNotEmpty);
      expect(h.fs.files.containsKey('/vault/.sync/users.json'), isFalse);
    });
  });

  group('addUserFromPublicKey —', () {
    late String memberPub;
    late String memberPriv;
    late String memberId;

    setUp(() async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.createVaultOnboarding(ownerName: 'Owner');
      final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
      memberPub = member.publicKeyBase64Url;
      memberPriv = member.privateKeyBase64Url;
    });

    test('the owner adds a member from a foreign public key and the file verifies', () async {
      final result = await h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: memberPub);

      expect(result.user, isNotNull);
      expect(result.user.publicKey, memberPub);
      expect(result.user.name, 'Member');
      expect(result.user.role, 'member');
      expect(result.user.addedBy, result.userRegistry.ownerUserId); // owner signs the record
      memberId = result.user.userId;

      // loadUserRegistry verifies the whole file under the owner key and the
      // member record under addedBy's (the owner's) key.
      final users = await h.registry.loadUserRegistry();
      expect(users, isNotNull);
      expect(users!.usersById[memberId], isNotNull);
      expect(users.usersById[users.ownerUserId]!.role, 'owner');
    });

    test('a padded standard-base64 key is normalized to base64url', () async {
      final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
      final paddedStandard = base64Encode(base64UrlDecode(member.publicKeyBase64Url));
      expect(paddedStandard, isNot(member.publicKeyBase64Url));

      final result = await h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: paddedStandard);
      expect(result.user.publicKey, member.publicKeyBase64Url);
    });

    test('rejects a key that is not 32 bytes', () async {
      final short = base64UrlEncodeNoPad(List<int>.filled(16, 7));
      await expectLater(h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: short), throwsArgumentError);
    });

    test('rejects a malformed key', () async {
      await expectLater(h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: 'not-a-key!!!'), throwsArgumentError);
    });

    test('adding a user from a foreign public key authorizes that user', () async {
      final added = await h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: memberPub);
      memberId = added.user.userId;

      // The member's own device: a certificate signed by the member's
      // identity key (the member generated it on their device).
      final deviceKey = await crypto.generateDeviceKeyPair();
      await _writeForeignDeviceFile(h, userId: memberId, userPrivKey: memberPriv, deviceUuid: 'member-device-uuid', devicePub: deviceKey.publicKeyBase64Url);

      final outcome = await _runChain(h, deviceUuid: 'member-device-uuid', observedKey: deviceKey.publicKeyBase64Url);
      expect(outcome.hasRejections, isFalse, reason: outcome.rejections.map((r) => r.toString()).join('; '));
      expect(outcome.accepted.keys.toSet(), {'member-device-uuid'});
    });

    test('revoking the user removes them from the authorization chain', () async {
      final added = await h.onboarding.addUserFromPublicKey(name: 'Member', publicKeyBase64Url: memberPub);
      memberId = added.user.userId;

      final deviceKey = await crypto.generateDeviceKeyPair();
      await _writeForeignDeviceFile(h, userId: memberId, userPrivKey: memberPriv, deviceUuid: 'member-device-uuid', devicePub: deviceKey.publicKeyBase64Url);

      // The owner tombstones the user in users.json (§3.6).
      final revoked = await h.onboarding.revokeUserOnboarding(memberId);
      expect(revoked.usersById[memberId]!.isRemoved, isTrue);
      // The tombstoned file still verifies under the signer (the owner).
      final loaded = await h.registry.loadUserRegistry();
      expect(loaded, isNotNull);
      expect(loaded!.usersById[memberId]!.isRemoved, isTrue);

      // The member's device is now rejected (unauthorized-user, §3.5.2) —
      // not merely unbound: the user is revoked, not the certificate.
      final outcome = await _runChain(h, deviceUuid: 'member-device-uuid', observedKey: deviceKey.publicKeyBase64Url);
      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections, hasLength(1));
      expect(outcome.rejections.single.reason, 'unauthorized-user');

      // The owner is unaffected.
      final ownerOutcome = await _runChain(h, deviceUuid: h.deviceService.currentDevice!.uuid, observedKey: h.deviceService.currentDevice!.publicKey!);
      expect(ownerOutcome.hasRejections, isFalse);
    });
  });

  group('revokeDeviceOnboarding —', () {
    test('the owner revokes their own device (tombstone, verified under the signer)', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final created = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      // The user gets a second device.
      final secondKey = await crypto.generateDeviceKeyPair();
      await h.registry.addDevice(deviceUuid: 'second-device-uuid', devicePublicKey: secondKey.publicKeyBase64Url, deviceName: 'Laptop');

      final revoked = await h.onboarding.revokeDeviceOnboarding('second-device-uuid');
      expect(revoked.devicesById['second-device-uuid']!.isRemoved, isTrue);
      expect(revoked.devicesById[created.device.uuid]!.isRemoved, isFalse); // the other device is untouched
      expect(revoked.devices, hasLength(2));

      // The tombstoned file verifies under the owner's identity key.
      final loaded = await h.registry.loadDeviceRegistry(created.owner.userId);
      expect(loaded, isNotNull);
      expect(loaded!.devicesById['second-device-uuid']!.isRemoved, isTrue);
    });

    test('a revoked device stops being authorized', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final created = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      final secondKey = await crypto.generateDeviceKeyPair();
      await h.registry.addDevice(deviceUuid: 'second-device-uuid', devicePublicKey: secondKey.publicKeyBase64Url, deviceName: 'Laptop');

      await h.onboarding.revokeDeviceOnboarding('second-device-uuid');

      final outcome = await _runChain(h, deviceUuid: 'second-device-uuid', observedKey: secondKey.publicKeyBase64Url);
      expect(outcome.accepted, isEmpty);
      expect(outcome.rejections.single.reason, 'unbound-device');

      // The first device remains authorized.
      final firstOutcome = await _runChain(h, deviceUuid: created.device.uuid, observedKey: created.device.publicKey);
      expect(firstOutcome.hasRejections, isFalse);
    });

    test('throws when the device is not in the operator registry', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      await expectLater(h.onboarding.revokeDeviceOnboarding('unknown-device'), throwsArgumentError);
    });
  });

  group('revokeUserOnboarding —', () {
    test('throws when users.json is absent', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await expectLater(h.onboarding.revokeUserOnboarding('nobody'), throwsStateError);
    });

    test('throws when the operator revokes the owner', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      final created = await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      await expectLater(h.onboarding.revokeUserOnboarding(created.owner.userId), throwsArgumentError);
    });

    test('throws when the target is not a member', () async {
      h = await _buildHarness(crypto: crypto, signing: signing);
      await h.onboarding.createVaultOnboarding(ownerName: 'Owner');

      await expectLater(h.onboarding.revokeUserOnboarding('stranger'), throwsArgumentError);
    });
  });

  group('active-vault guard —', () {
    test('every flow throws when no vault is open', () async {
      final fs = _OnboardFs();
      final keyStore = FakeSecureKeyStore();
      final idService = FakeIdService();
      final deviceService = _RecordingDeviceService(fs, crypto, keyStore);
      final userService = UserServiceImpl(fs, idService, crypto, keyStore);
      final vault = VaultSystem(fs, FakeVaultRepository(), idService, deviceService);
      final hlcService = HlcService(vault, deviceService);
      final registry = RegistryServiceImpl(fileSystem: fs, hlcService: hlcService, crypto: crypto, secureKeyStore: keyStore, vaultSystem: vault);
      final onboarding = OnboardingServiceImpl(
        fileSystem: fs,
        deviceService: deviceService,
        userService: userService,
        registry: registry,
        crypto: crypto,
        idService: idService,
        vaultSystem: vault,
      );
      // No vault opened: currentVault stays null.
      expect(vault.currentVault.value, isNull);

      await expectLater(onboarding.createVaultOnboarding(ownerName: 'O'), throwsStateError);
      await expectLater(onboarding.bootstrapOwnerIdentity(ownerName: 'O'), throwsStateError);
      await expectLater(onboarding.restoreFromSeed(mnemonic: _memberMnemonic(List.generate(32, (i) => i + 1))), throwsStateError);
      await expectLater(onboarding.addUserFromPublicKey(name: 'M', publicKeyBase64Url: 'x'), throwsStateError);
      await expectLater(onboarding.revokeDeviceOnboarding('d'), throwsStateError);
      await expectLater(onboarding.revokeUserOnboarding('u'), throwsStateError);

      _vaultsToDispose.add(vault);
    });
  });
}
