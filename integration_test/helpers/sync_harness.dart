// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
//
// NOET-34 integration-test harness.
//
// Models "two devices / two users sharing one vault" the way the issue's
// context pack asks: each device is a real on-disk vault folder with its own
// `.noetec/` (local: device.json / identity.json / trusted_keys.json) and its
// own `.sync/` (shared: oplog + registry). The shared area is reconciled by
// copying one side's `.sync/` onto the other's (the issue's "drive sync by
// writing one side's .sync/ and letting the other reconcile").
//
// Everything under test is the REAL production stack:
//   * OpLogSigner  / OpLogWriter   (real Ed25519 signing + wire encode to disk)
//   * OpLogReader  / OpLogVerifier (real signature verify + chain rejection)
//   * OpLogAuthorizer + TrustStore (real TOFU + certificate + registry filter)
//   * RegistryService / OnboardingService (real registry signing)
//   * OpLogDag / MergeEngine / StateReconstructionEngine (real merge)
// The only fakes are the secure-storage boundary (InMemorySecureKeyStore —
// flutter_secure_storage is unavailable in the test env) and the vault-recent
// list (a no-op IVaultRepository). No app logic is faked.
library;

import 'dart:io';

import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/onboarding_service.dart';
import 'package:noetec/service/user_service.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_reader.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';
import 'package:noetec/systems/oplog_system/oplog_verifier.dart';
import 'package:noetec/systems/oplog_system/oplog_writer.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:noetec/service/trust_store.dart';

import 'in_memory_secure_key_store.dart';

/// A one-shot in-memory vault-recent repository (the real one needs a settings
/// service; the recent list is irrelevant to sync).
class _NoopVaultRepository implements IVaultRepository {
  @override
  Future<List<VaultEntity>> loadRecentVaults() async => const [];
  @override
  Future<void> saveRecentVaults(List<VaultEntity> vaults) async {}
  @override
  Future<void> addToRecent(VaultEntity vault) async {}
  @override
  Future<void> removeFromRecent(String vaultId) async {}
}

/// One real on-disk "device": its own vault folder (`.noetec/` + `.sync/`),
/// its own Ed25519 device key pair (private key in its own
/// [InMemorySecureKeyStore]), and real OpLog write/read/verify plumbing
/// against that folder.
final class SyncDevice {
  SyncDevice({
    required this.folderPath,
    required this.vaultId,
    required this.deviceUuid,
    required this.publicKey,
    required this.deviceName,
    required this.devicePrivateKey,
    required CryptoServiceImpl crypto,
    required IFileSystemService fileSystem,
    required InMemorySecureKeyStore keyStore,
  })  : _crypto = crypto,
        _fileSystem = fileSystem,
        _keyStore = keyStore,
        _serializer = const OpLogSerializer() {
    _signer = OpLogSigner(crypto: _crypto, secureKeyStore: _keyStore, serializer: _serializer);
    _writer = OpLogWriter(
      _fileSystem,
      folderPath,
      _serializer,
      signer: _signer,
      vaultId: vaultId,
      devicePublicKeyBase64Url: publicKey,
    );
    // keyResolver only matters for an all-legacy file (no pubKey on any
    // entry); for the local device we can resolve our own key. Remote devices
    // carry their key on their first entry, so this is a no-op for them.
    _verifier = OpLogVerifier(crypto: _crypto, serializer: _serializer, keyResolver: (id) => id == deviceUuid ? publicKey : null);
    _reader = OpLogReader(_fileSystem, folderPath, _serializer, verifier: _verifier);
  }

  final String folderPath;
  final String vaultId;
  final String deviceUuid;
  final String publicKey;
  final String deviceName;
  final String devicePrivateKey;

  final CryptoServiceImpl _crypto;
  final IFileSystemService _fileSystem;
  final InMemorySecureKeyStore _keyStore;

  final OpLogSerializer _serializer;
  late final OpLogSigner _signer;
  late final OpLogWriter _writer;
  late final OpLogVerifier _verifier;
  late final OpLogReader _reader;

  /// The on-disk `.sync/` directory (the shared, synced area).
  String get syncDir => '$folderPath/.sync';

  /// The `.noetec/` local directory.
  String get localDir => '$folderPath/.noetec';

  /// The oplog file path for [relativePath] on THIS device (in the shared `.sync/`).
  String oplogFilePath(String relativePath) => '$syncDir/$relativePath/$deviceUuid.oplog.jsonl';

  /// Appends [entry] to this device's oplog file for [relativePath], signing
  /// it with this device's real key (the real OpLogSigner + OpLogWriter path).
  Future<void> append(String relativePath, OpLogEntry entry) => _writer.append(relativePath, entry);

  /// Signs [entry] with THIS device's real key (pubKey set only when
  /// [entry].parent is null) and appends it to an EXPLICIT [targetFilePath] —
  /// used to model a forger appending into a *victim's* oplog file under a
  /// different signature key.
  Future<void> appendSignedTo(String relativePath, String targetFilePath, OpLogEntry entry) async {
    final signed = await _signer.sign(entry, relativePath, vaultId: vaultId, devicePublicKeyBase64Url: publicKey);
    final line = _serializer.encode(signed);
    await _fileSystem.appendToFile(targetFilePath, '$line\n');
  }

  /// Reads every device file for [relativePath] from this device's `.sync/`
  /// and returns the signature-verified entries (the real OpLogVerifier chain
  /// rejection applies). This is the read side of the sync pipeline.
  Future<Map<String, List<OpLogEntry>>> readAllVerified(String relativePath) => _reader.readAllLogs(relativePath);

  /// Builds the DAG over the verified entries (the same input the app's
  /// `SyncSystem.checkFile` feeds to `MergeEngine.merge`).
  Future<OpLogDag> buildDag(String relativePath) async {
    final logs = await readAllVerified(relativePath);
    return OpLogDag.fromEntries(logs);
  }
}

/// Builds a fresh real on-disk device in a temp folder with a real Ed25519 key
/// pair (private key stored in its own [InMemorySecureKeyStore]).
Future<SyncDevice> createDevice({
  required String folderPath,
  required String vaultId,
  required String deviceName,
  required CryptoServiceImpl crypto,
  required IFileSystemService fileSystem,
}) async {
  final keyStore = InMemorySecureKeyStore();
  final keyPair = await crypto.generateDeviceKeyPair();
  final deviceUuid = IdService().generateId();
  await fileSystem.createDirectory('$folderPath/.noetec');
  await fileSystem.createDirectory('$folderPath/.sync');
  final identity = DeviceIdentity(uuid: deviceUuid, name: deviceName, createdAt: DateTime.now(), lastHlc: null, publicKey: keyPair.publicKeyBase64Url);
  final deviceJson = {
    'uuid': deviceUuid,
    'name': deviceName,
    'created_at': identity.createdAt.toIso8601String(),
    'last_hlc': null,
    'public_key': keyPair.publicKeyBase64Url,
  };
  await fileSystem.writeFile('$folderPath/.noetec/device.json', _jsonEncode(deviceJson));
  await keyStore.storeDevicePrivateKey(vaultId, keyPair.privateKeyBase64Url);
  return SyncDevice(
    folderPath: folderPath,
    vaultId: vaultId,
    deviceUuid: deviceUuid,
    publicKey: keyPair.publicKeyBase64Url,
    deviceName: deviceName,
    devicePrivateKey: keyPair.privateKeyBase64Url,
    crypto: crypto,
    fileSystem: fileSystem,
    keyStore: keyStore,
  );
}

String _jsonEncode(Object? o) {
  final buf = StringBuffer();
  _encode(o, buf);
  return buf.toString();
}

void _encode(Object? o, StringBuffer buf) {
  if (o == null) {
    buf.write('null');
  } else if (o is String) {
    buf.write('"${o.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"');
  } else if (o is num || o is bool) {
    buf.write(o.toString());
  } else if (o is Map) {
    buf.write('{');
    var first = true;
    o.forEach((k, v) {
      if (!first) buf.write(',');
      first = false;
      _encode(k, buf);
      buf.write(':');
      _encode(v, buf);
    });
    buf.write('}');
  } else if (o is List) {
    buf.write('[');
    for (var i = 0; i < o.length; i++) {
      if (i > 0) buf.write(',');
      _encode(o[i], buf);
    }
    buf.write(']');
  }
}

/// Copies [src]'s shared `.sync/` area onto [dst]'s — the deterministic
/// stand-in for the sync backend delivering one side's changes to the other
/// (the issue's "writing one side's .sync/ and letting the other reconcile").
Future<void> syncFrom(SyncDevice src, SyncDevice dst) async {
  final srcDir = Directory(src.syncDir);
  final dstDir = Directory(dst.syncDir);
  if (!await srcDir.exists()) return;
  await dstDir.create(recursive: true);
  await _copyTree(srcDir, dstDir);
}

Future<void> _copyTree(Directory src, Directory dst) async {
  await for (final entity in src.list()) {
    final target = '${dst.path}/${entity.path.split(Platform.pathSeparator).last}';
    if (entity is Directory) {
      await _copyTree(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}

/// A block helper (id + plain text) used across the scenario tests.
TextBlockEntity blk(String id, String text) => TextBlockEntity(id: id, segments: [TextSegment(text: text)]);

/// A real owner "user device": the [SyncDevice] plus a real owner identity and
/// a real, correctly-signed registry (`.sync/users.json` +
/// `.sync/devices/<owner>.json`) built by the real OnboardingService.
final class OwnerDevice {
  OwnerDevice({required this.device, required this.ownerUserId, required this.ownerName, required this.registry, required this.trustStore, required this.keyStore});

  final SyncDevice device;
  final String ownerUserId;
  final String ownerName;
  final IRegistryService registry;
  final ITrustStore trustStore;
  final InMemorySecureKeyStore keyStore;
}

/// Builds a real on-boarded owner vault in [folderPath]: owner identity +
/// first device + `users.json` + `devices/<owner>.json`, all signed by the
/// real OnboardingService / RegistryService against the real crypto stack.
Future<OwnerDevice> createOwnerVault({
  required String folderPath,
  required String vaultId,
  required String ownerName,
  required String deviceName,
  required CryptoServiceImpl crypto,
  required IFileSystemService fileSystem,
}) async {
  final device = await createDevice(folderPath: folderPath, vaultId: vaultId, deviceName: deviceName, crypto: crypto, fileSystem: fileSystem);
  final keyStore = InMemorySecureKeyStore();
  // The owner's device private key must be in the key store the registry /
  // onboarding services read from (keyed by vaultId).
  await keyStore.storeDevicePrivateKey(vaultId, device.devicePrivateKey);

  final idService = IdService();
  final deviceService = DeviceServiceImpl(fileSystem, idService, crypto, keyStore);
  final userService = UserServiceImpl(fileSystem, idService, crypto, keyStore);
  final vaultSystem = VaultSystem(fileSystem, _NoopVaultRepository(), idService, deviceService);
  final hlcService = HlcService(vaultSystem, deviceService);
  // Construct the registry + onboarding BEFORE activating the vault so their
  // `currentVault` listeners fire when `currentVault.value` is set below
  // (the developer's UserDeviceHarness uses this exact order).
  final registry = RegistryServiceImpl(fileSystem: fileSystem, hlcService: hlcService, crypto: crypto, secureKeyStore: keyStore, vaultSystem: vaultSystem);
  final onboarding = OnboardingServiceImpl(fileSystem: fileSystem, deviceService: deviceService, userService: userService, registry: registry, crypto: crypto, idService: idService, vaultSystem: vaultSystem);

  await deviceService.ensureDevice(folderPath, vaultId);
  vaultSystem.currentVault.value = VaultEntity(id: vaultId, name: 'Vault', rootPath: folderPath, createdAt: DateTime(2026));

  final result = await onboarding.createVaultOnboarding(ownerName: ownerName, deviceName: deviceName);

  final trustStore = TrustStoreImpl(fileSystem);
  return OwnerDevice(device: device, ownerUserId: result.owner.userId, ownerName: ownerName, registry: registry, trustStore: trustStore, keyStore: keyStore);
}

/// The 8-hex node id embedded in an HLC key (HlcService uses
/// `device.truncatedDeviceId` — the UUID with hyphens stripped). The HLC key
/// format is `physicalMs-counterHex-deviceId` and `Hlc.fromKey` splits on `-`
/// expecting exactly 3 parts, so the HLC device id MUST be hyphen-free.
String nodeId(String uuid) => uuid.replaceAll('-', '').substring(0, 8);

/// A signed [OpLogEntry] with a deterministic HLC, used to build the
/// shared-ancestor / divergent DAG structures the real merge engine consumes.
///
/// [deviceId] is the full UUID (the OpLogEntry attribution key + oplog file
/// name); the HLC carries only its [nodeId] form.
OpLogEntry entry({
  required int physicalMs,
  required String deviceId,
  Hlc? parent,
  Hlc? parentB,
  required OpEntryType type,
  List<BlockOp>? blockOps,
  FileOp? fileOp,
  String? fileHash,
}) {
  return OpLogEntry(version: 1, hlc: Hlc(physicalMs: physicalMs, counter: 0, deviceId: nodeId(deviceId)), parent: parent, parentB: parentB, type: type, blockOps: blockOps, fileOp: fileOp, fileHash: fileHash, deviceId: deviceId);
}

/// A 32-byte base64url Ed25519 public key derived from [seed] (a valid,
/// deterministic key — used to model a foreign/attacker device).
String foreignKey(int seed) {
  final bytes = List<int>.generate(32, (i) => (seed * 13 + i * 7) & 0xff);
  return base64UrlEncodeNoPad(bytes);
}

/// Makes a second device that shares [anchor]'s vault folder (its `.sync/`
/// area is the same shared area), but has its OWN Ed25519 key pair and its OWN
/// in-memory key store — i.e. a legitimate second device of the same user.
Future<SyncDevice> makeSharedDevice({
  required SyncDevice anchor,
  required String name,
  required CryptoServiceImpl crypto,
  required IFileSystemService fileSystem,
}) async {
  final ks = InMemorySecureKeyStore();
  final kp = await crypto.generateDeviceKeyPair();
  final uuid = IdService().generateId();
  final vid = 'shared-${uuid}';
  await ks.storeDevicePrivateKey(vid, kp.privateKeyBase64Url);
  return SyncDevice(
    folderPath: anchor.folderPath,
    vaultId: vid,
    deviceUuid: uuid,
    publicKey: kp.publicKeyBase64Url,
    deviceName: name,
    devicePrivateKey: kp.privateKeyBase64Url,
    crypto: crypto,
    fileSystem: fileSystem,
    keyStore: ks,
  );
}
