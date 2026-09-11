// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:canonical_json/canonical_json.dart' as cj;
import 'package:logging/logging.dart';
import 'package:noetec/service/crypto_service.dart';

import 'registry_models.dart';
import 'registry_record.dart';

/// Resolves a user's base64url Ed25519 **identity** public key for registry
/// verification (sync-security.md §3.4 "Key resolution").
///
/// The owner's identity key is the root of trust (TOFU-pinned in NOET-30);
/// other users' keys resolve from their `users.json` record. NOET-29 keeps
/// this as an injectable interface so the production wiring (TOFU store +
/// registry lookup) lands in NOET-30 without changing the reconciler.
abstract interface class IRegistryKeyProvider {
  /// The base64url identity public key for [userId], or `null` if unknown.
  Future<String?> identityKeyFor(String userId);
}

/// A single verification problem found in a registry file (spec §3.4, §9).
final class RegistryVerificationIssue {
  const RegistryVerificationIssue({required this.scope, required this.message});

  /// What failed: `'file'` (whole-file signature/structure) or a record id.
  final String scope;

  /// A human-readable description (logged via `package:logging`, §9).
  final String message;

  @override
  String toString() => '$scope: $message';
}

/// The outcome of verifying one registry file.
final class RegistryVerificationResult {
  const RegistryVerificationResult({required this.valid, this.issues = const []});

  /// `true` when the whole-file signature and every record signature
  /// verified under the correct keys.
  final bool valid;

  /// The problems found (empty when [valid]).
  final List<RegistryVerificationIssue> issues;
}

/// Signs and verifies the two registry files (sync-security.md §3.2–§3.4).
///
/// Per spec §3.2/§3.3 the signing input is the plain OLPC canonical JSON of
/// the unsigned object — **without** a document path (unlike Phase-1 OpLog
/// entries, §2.2) — so:
/// - a record's `signature` = Ed25519 over `canonicalJson(recordWithoutSignature)`;
/// - a file's `signature` = Ed25519 over `canonicalJson(fileWithoutSignature)`.
class RegistrySigning {
  RegistrySigning(this._crypto, [Logger? log]) : _log = log ?? Logger('RegistrySigning');

  final ICryptoService _crypto;
  final Logger _log;

  /// Canonical-JSON byte sequences (the signing/verification input).
  List<int> _recordInput(RegistryRecord record) => cj.canonicalJson.encode(record.toUnsignedWireMap());

  List<int> _userFileInput(UserRegistry file) => cj.canonicalJson.encode(file.toUnsignedWireMap());

  List<int> _deviceFileInput(DeviceRegistry file) => cj.canonicalJson.encode(file.toUnsignedWireMap());

  /// Verifies a single record signature under [publicKeyBase64Url] (base64url
  /// Ed25519). Used by the service's file-attested record pass (the whole-file
  /// signature already verified, so the file's listed keys are trusted, §3.4).
  Future<bool> verifyRecord(RegistryRecord record, String publicKeyBase64Url) =>
      _crypto.verify(publicKeyBase64Url, _recordInput(record), record.toWireMap()['signature'] as String);

  /// Signs every user record (with the `addedBy` key) and the whole file
  /// (with the [ownerPrivateKey]) and returns the signed registry.
  ///
  /// [recordKeys] maps a `userId` to the base64url **private** key that signs
  /// records whose `addedBy` is that user.
  Future<UserRegistry> signUserRegistry(UserRegistry file, {required String ownerPrivateKey, required Map<String, String> recordKeys}) async {
    final signedUsers = <UserRecord>[];
    for (final user in file.users) {
      final privateKey = recordKeys[user.addedBy];
      if (privateKey == null) {
        throw ArgumentError('no signing key for addedBy "${user.addedBy}" (user ${user.userId})');
      }
      final signature = await _crypto.sign(privateKey, _recordInput(user));
      signedUsers.add(_userWithSignature(user, signature));
    }
    final unsignedFile = UserRegistry(version: file.version, revision: file.revision, parent: file.parent, ownerUserId: file.ownerUserId, users: signedUsers, signature: '');
    final fileSignature = await _crypto.sign(ownerPrivateKey, _userFileInput(unsignedFile));
    return unsignedFile.withFileSignature(fileSignature);
  }

  /// Signs a single user record (with the `addedBy`/operator [privateKey])
  /// and returns the record carrying its signature.
  Future<UserRecord> signUserRecord(UserRecord record, String privateKey) async {
    final signature = await _crypto.sign(privateKey, _recordInput(record));
    return _userWithSignature(record, signature);
  }

  /// Signs a single device record (with the owning user's [privateKey]) and
  /// returns the record carrying its signature.
  Future<DeviceRecord> signDeviceRecord(DeviceRecord record, String privateKey) async {
    final signature = await _crypto.sign(privateKey, _recordInput(record));
    return _deviceWithSignature(record, signature);
  }

  /// Adds the whole-file signature (with [ownerPrivateKey]) to a user registry
  /// whose records **already** carry their per-record signatures. Used for the
  /// merge result (authors' record signatures are preserved, §3.2).
  Future<UserRegistry> signUserFileOnly(UserRegistry file, {required String ownerPrivateKey}) async {
    final fileSignature = await _crypto.sign(ownerPrivateKey, _userFileInput(file));
    return file.withFileSignature(fileSignature);
  }

  /// Adds the whole-file signature (with [userPrivateKey]) to a device
  /// registry whose records **already** carry their per-record signatures.
  /// Used for the merge result (the owner's record signatures are preserved,
  /// §3.3).
  Future<DeviceRegistry> signDeviceFileOnly(DeviceRegistry file, {required String userPrivateKey}) async {
    final fileSignature = await _crypto.sign(userPrivateKey, _deviceFileInput(file));
    return file.withFileSignature(fileSignature);
  }

  /// Signs every device record and the whole file (both with the owning
  /// user's [userPrivateKey]) and returns the signed registry.
  Future<DeviceRegistry> signDeviceRegistry(DeviceRegistry file, {required String userPrivateKey}) async {
    final signedDevices = <DeviceRecord>[];
    for (final device in file.devices) {
      final signature = await _crypto.sign(userPrivateKey, _recordInput(device));
      signedDevices.add(_deviceWithSignature(device, signature));
    }
    final unsignedFile = DeviceRegistry(version: file.version, revision: file.revision, parent: file.parent, userId: file.userId, devices: signedDevices, signature: '');
    final fileSignature = await _crypto.sign(userPrivateKey, _deviceFileInput(unsignedFile));
    return unsignedFile.withFileSignature(fileSignature);
  }

  /// Verifies the whole-file signature (under the owner's key) and every
  /// record signature (under its `addedBy`'s key). Any failure is collected
  /// in [RegistryVerificationResult.issues] and logged (§9).
  Future<RegistryVerificationResult> verifyUserRegistry(UserRegistry file, IRegistryKeyProvider keys) async {
    final issues = <RegistryVerificationIssue>[];

    final ownerKey = await keys.identityKeyFor(file.ownerUserId);
    if (ownerKey == null) {
      issues.add(RegistryVerificationIssue(scope: 'file', message: 'no identity key for the owner "${file.ownerUserId}"'));
      return RegistryVerificationResult(valid: false, issues: issues);
    }
    final fileOk = await _crypto.verify(ownerKey, _userFileInput(file), file.signature);
    if (!fileOk) {
      issues.add(const RegistryVerificationIssue(scope: 'file', message: 'whole-file signature failed under the owner key'));
    }

    for (final user in file.users) {
      final addedByKey = await keys.identityKeyFor(user.addedBy);
      if (addedByKey == null) {
        issues.add(RegistryVerificationIssue(scope: user.userId, message: 'no identity key for addedBy "${user.addedBy}"'));
        continue;
      }
      final recordOk = await _crypto.verify(addedByKey, _recordInput(user), user.signature);
      if (!recordOk) {
        issues.add(RegistryVerificationIssue(scope: user.userId, message: 'record signature failed under addedBy "${user.addedBy}"'));
      }
    }

    if (issues.isNotEmpty) {
      _log.warning('users.json verification failed: ${issues.map((i) => i.toString()).join('; ')}');
    }
    return RegistryVerificationResult(valid: issues.isEmpty, issues: issues);
  }

  /// Verifies the whole-file signature (under the owning user's key) and every
  /// record signature (also under the owning user's key).
  Future<RegistryVerificationResult> verifyDeviceRegistry(DeviceRegistry file, IRegistryKeyProvider keys) async {
    final issues = <RegistryVerificationIssue>[];

    final userKey = await keys.identityKeyFor(file.userId);
    if (userKey == null) {
      issues.add(RegistryVerificationIssue(scope: 'file', message: 'no identity key for the owning user "${file.userId}"'));
      return RegistryVerificationResult(valid: false, issues: issues);
    }
    final fileOk = await _crypto.verify(userKey, _deviceFileInput(file), file.signature);
    if (!fileOk) {
      issues.add(const RegistryVerificationIssue(scope: 'file', message: 'whole-file signature failed under the user key'));
    }

    for (final device in file.devices) {
      final recordOk = await _crypto.verify(userKey, _recordInput(device), device.signature);
      if (!recordOk) {
        issues.add(RegistryVerificationIssue(scope: device.deviceUuid, message: 'record signature failed under the user key'));
      }
    }

    if (issues.isNotEmpty) {
      _log.warning('devices/${file.userId}.json verification failed: ${issues.map((i) => i.toString()).join('; ')}');
    }
    return RegistryVerificationResult(valid: issues.isEmpty, issues: issues);
  }
}

// Records are `final class` (immutable) with all fields required, so a
// "copy with signature" is a fresh construction.

UserRecord _userWithSignature(UserRecord record, String signature) => UserRecord(
  userId: record.userId,
  name: record.name,
  publicKey: record.publicKey,
  role: record.role,
  addedBy: record.addedBy,
  updatedAt: record.updatedAt,
  removedAt: record.removedAt,
  signature: signature,
);

DeviceRecord _deviceWithSignature(DeviceRecord record, String signature) => DeviceRecord(
  deviceUuid: record.deviceUuid,
  devicePublicKey: record.devicePublicKey,
  userId: record.userId,
  deviceName: record.deviceName,
  issuedAt: record.issuedAt,
  updatedAt: record.updatedAt,
  removedAt: record.removedAt,
  signature: signature,
);
