// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/hlc.dart';

import 'registry_record.dart';

/// A user entry in the user registry (sync-security.md §3.2).
///
/// Wire keys (camelCase, exactly as the spec shows): `userId`, `name`,
/// `publicKey`, `role`, `addedBy`, `updatedAt`, `removedAt`, `signature`.
/// The per-record signature covers the record **without** its `signature`
/// field (the canonical JSON of [toUnsignedWireMap]) and is produced by
/// `addedBy`'s identity key.
final class UserRecord implements RegistryRecord {
  const UserRecord({
    required this.userId,
    required this.name,
    required this.publicKey,
    required this.role,
    required this.addedBy,
    required this.updatedAt,
    required this.removedAt,
    required this.signature,
  });

  /// The user's UUID. Unique within the registry; the record's merge key.
  final String userId;

  /// Display name.
  final String name;

  /// The user's base64url Ed25519 identity public key (§2.1).
  final String publicKey;

  /// `owner` or `member`. The owner's record MUST carry `owner` (§3.2).
  final String role;

  /// The `userId` whose identity key signs this record.
  final String addedBy;

  /// HLC key of the last change to this record.
  final Hlc updatedAt;

  /// HLC key at which the user was removed, or `null` (a tombstone, §3.6).
  final Hlc? removedAt;

  /// Base64url Ed25519 signature over [toUnsignedWireMap] by `addedBy`.
  final String signature;

  bool get isRemoved => removedAt != null;

  /// The HLC used for LWW comparison: a tombstone is ordered by `removedAt`
  /// (the newest stamp), a live record by `updatedAt` (§3.7).
  @override
  Hlc get changeHlc => removedAt ?? updatedAt;

  /// The record's merge key.
  @override
  String get recordId => userId;

  /// The full wire form of the record (all eight spec keys; `removedAt` is
  /// the JSON token `null` when unset — nulls are never omitted, §2.2).
  @override
  Map<String, dynamic> toWireMap() => {
    'userId': userId,
    'name': name,
    'publicKey': publicKey,
    'role': role,
    'addedBy': addedBy,
    'updatedAt': updatedAt.toKey(),
    'removedAt': removedAt?.toKey(),
    'signature': signature,
  };

  /// The wire form **without** `signature` — the per-record signing input
  /// (spec §3.2).
  @override
  Map<String, dynamic> toUnsignedWireMap() {
    final map = toWireMap();
    map.remove('signature');
    return map;
  }

  factory UserRecord.fromWireMap(Map<String, dynamic> json) {
    return UserRecord(
      userId: _string(json, 'userId'),
      name: _string(json, 'name'),
      publicKey: _string(json, 'publicKey'),
      role: _string(json, 'role'),
      addedBy: _string(json, 'addedBy'),
      updatedAt: _hlc(json, 'updatedAt'),
      removedAt: json['removedAt'] is String ? Hlc.fromKey(json['removedAt'] as String) : null,
      signature: _string(json, 'signature'),
    );
  }
}

/// A device certificate entry in a device registry (sync-security.md §3.3).
///
/// Wire keys: `deviceUuid`, `devicePublicKey`, `userId`, `deviceName`,
/// `issuedAt`, `updatedAt`, `removedAt`, `signature`. The record is a
/// device certificate (the per-record `userId` and `issuedAt` are part of
/// the certificate, §3.3) plus merge fields. Signed by the owning user's
/// identity key.
final class DeviceRecord implements RegistryRecord {
  const DeviceRecord({
    required this.deviceUuid,
    required this.devicePublicKey,
    required this.userId,
    required this.deviceName,
    required this.issuedAt,
    required this.updatedAt,
    required this.removedAt,
    required this.signature,
  });

  /// The device's UUID. Unique within the file; the record's merge key.
  final String deviceUuid;

  /// The device's base64url Ed25519 public key (§2.1).
  final String devicePublicKey;

  /// The owning user; MUST equal the file's `userId`.
  final String userId;

  /// Display name.
  final String deviceName;

  /// HLC key at which the device was bound to the user (certificate).
  final Hlc issuedAt;

  /// HLC key of the last change to this record.
  final Hlc updatedAt;

  /// HLC key at which the device was revoked, or `null` (a tombstone, §3.6).
  final Hlc? removedAt;

  /// Base64url Ed25519 signature over [toUnsignedWireMap] by the owning
  /// user's identity key.
  final String signature;

  bool get isRemoved => removedAt != null;

  /// The HLC used for LWW comparison (tombstone by `removedAt`, else
  /// `updatedAt`, §3.7).
  @override
  Hlc get changeHlc => removedAt ?? updatedAt;

  /// The record's merge key.
  @override
  String get recordId => deviceUuid;

  @override
  Map<String, dynamic> toWireMap() => {
    'deviceUuid': deviceUuid,
    'devicePublicKey': devicePublicKey,
    'userId': userId,
    'deviceName': deviceName,
    'issuedAt': issuedAt.toKey(),
    'updatedAt': updatedAt.toKey(),
    'removedAt': removedAt?.toKey(),
    'signature': signature,
  };

  /// The wire form **without** `signature` — the per-record signing input
  /// (spec §3.3).
  @override
  Map<String, dynamic> toUnsignedWireMap() {
    final map = toWireMap();
    map.remove('signature');
    return map;
  }

  factory DeviceRecord.fromWireMap(Map<String, dynamic> json) {
    return DeviceRecord(
      deviceUuid: _string(json, 'deviceUuid'),
      devicePublicKey: _string(json, 'devicePublicKey'),
      userId: _string(json, 'userId'),
      deviceName: _string(json, 'deviceName'),
      issuedAt: _hlc(json, 'issuedAt'),
      updatedAt: _hlc(json, 'updatedAt'),
      removedAt: json['removedAt'] is String ? Hlc.fromKey(json['removedAt'] as String) : null,
      signature: _string(json, 'signature'),
    );
  }
}

/// The user registry: `.sync/users.json` (sync-security.md §3.2).
///
/// Whole-file signature by the **owner's** identity key over the canonical
/// JSON of the file without its top-level `signature` field.
final class UserRegistry {
  const UserRegistry({required this.version, required this.revision, required this.parent, required this.ownerUserId, required this.users, required this.signature});

  /// Format version; MUST be `1` (validate()).
  final int version;

  /// HLC key stamping this file version.
  final Hlc revision;

  /// HLC key of the previous revision, or `null` on the first (§3.7).
  final Hlc? parent;

  /// The `userId` that administers this registry.
  final String ownerUserId;

  /// The user records (empty is valid).
  final List<UserRecord> users;

  /// Base64url whole-file signature by the owner's identity key.
  final String signature;

  /// The registry's file name relative to `.sync/`.
  String get fileKey => 'users.json';

  /// The records keyed by [UserRecord.recordId].
  Map<String, UserRecord> get usersById {
    final map = <String, UserRecord>{};
    for (final user in users) {
      map[user.userId] = user;
    }
    return map;
  }

  Map<String, dynamic> toWireMap() => {
    'version': version,
    'revision': revision.toKey(),
    'parent': parent?.toKey(),
    'owner_user_id': ownerUserId,
    'users': [for (final user in users) user.toWireMap()],
    'signature': signature,
  };

  /// The wire form **without** the top-level `signature` — the whole-file
  /// signing input (spec §3.2).
  Map<String, dynamic> toUnsignedWireMap() {
    final map = toWireMap();
    map.remove('signature');
    return map;
  }

  /// Returns a copy with the top-level [signature] replaced.
  UserRegistry withFileSignature(String signature) =>
      UserRegistry(version: version, revision: revision, parent: parent, ownerUserId: ownerUserId, users: users, signature: signature);

  factory UserRegistry.fromWireMap(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw FormatException('"version" must be an integer, got: $version');
    }
    final usersJson = json['users'];
    if (usersJson is! List) {
      throw const FormatException('"users" must be a list');
    }
    return UserRegistry(
      version: version,
      revision: _hlc(json, 'revision'),
      parent: json['parent'] is String ? Hlc.fromKey(json['parent'] as String) : null,
      ownerUserId: _string(json, 'owner_user_id'),
      users: [for (final entry in usersJson) UserRecord.fromWireMap(_recordMap(entry, 'user record'))],
      signature: _string(json, 'signature'),
    );
  }

  /// Structural validation independent of signatures (sync-security.md §3.2):
  /// the version must be 1, roles must be `owner`/`member`, user ids unique,
  /// and the owner's record must exist and carry the `owner` role.
  void validate() {
    if (version != 1) {
      throw FormatException('unsupported users.json version $version (expected 1)');
    }
    final seen = <String>{};
    UserRecord? ownerRecord;
    for (final user in users) {
      if (user.role != 'owner' && user.role != 'member') {
        throw FormatException('user ${user.userId} has invalid role "${user.role}" (expected owner|member)');
      }
      if (!seen.add(user.userId)) {
        throw FormatException('duplicate userId ${user.userId} in users.json');
      }
      if (user.userId == ownerUserId) {
        ownerRecord = user;
      }
    }
    if (ownerRecord == null) {
      throw FormatException('users.json has no record for the owner_user_id $ownerUserId');
    }
    if (ownerRecord.role != 'owner') {
      throw FormatException('the owner record ${ownerRecord.userId} must carry the "owner" role, got "${ownerRecord.role}"');
    }
  }
}

/// A per-user device registry: `.sync/devices/<userId>.json` (spec §3.3).
///
/// Whole-file signature by the **owning user's** identity key over the
/// canonical JSON of the file without its top-level `signature` field. The
/// unique file name makes the registry conflict-free between users; two
/// devices of the same user merge with the same LWW rules as `users.json`.
final class DeviceRegistry {
  const DeviceRegistry({required this.version, required this.revision, required this.parent, required this.userId, required this.devices, required this.signature});

  final int version;
  final Hlc revision;
  final Hlc? parent;

  /// The user this file belongs to; MUST equal the `userId` in the file name.
  final String userId;

  /// The device certificate records (empty is valid).
  final List<DeviceRecord> devices;

  /// Base64url whole-file signature by the owning user's identity key.
  final String signature;

  /// The registry's file name relative to `.sync/`.
  String get fileKey => 'devices/$userId.json';

  /// The records keyed by [DeviceRecord.recordId].
  Map<String, DeviceRecord> get devicesById {
    final map = <String, DeviceRecord>{};
    for (final device in devices) {
      map[device.deviceUuid] = device;
    }
    return map;
  }

  Map<String, dynamic> toWireMap() => {
    'version': version,
    'revision': revision.toKey(),
    'parent': parent?.toKey(),
    'userId': userId,
    'devices': [for (final device in devices) device.toWireMap()],
    'signature': signature,
  };

  /// The wire form **without** the top-level `signature` — the whole-file
  /// signing input (spec §3.3).
  Map<String, dynamic> toUnsignedWireMap() {
    final map = toWireMap();
    map.remove('signature');
    return map;
  }

  /// Returns a copy with the top-level [signature] replaced.
  DeviceRegistry withFileSignature(String signature) =>
      DeviceRegistry(version: version, revision: revision, parent: parent, userId: userId, devices: devices, signature: signature);

  factory DeviceRegistry.fromWireMap(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw FormatException('"version" must be an integer, got: $version');
    }
    final devicesJson = json['devices'];
    if (devicesJson is! List) {
      throw const FormatException('"devices" must be a list');
    }
    return DeviceRegistry(
      version: version,
      revision: _hlc(json, 'revision'),
      parent: json['parent'] is String ? Hlc.fromKey(json['parent'] as String) : null,
      userId: _string(json, 'userId'),
      devices: [for (final entry in devicesJson) DeviceRecord.fromWireMap(_recordMap(entry, 'device record'))],
      signature: _string(json, 'signature'),
    );
  }

  /// Structural validation independent of signatures (sync-security.md
  /// §3.3): the version must be 1, every record's `userId` must equal the
  /// file's `userId`, and device UUIDs must be unique.
  void validate() {
    if (version != 1) {
      throw FormatException('unsupported devices registry version $version (expected 1)');
    }
    final seen = <String>{};
    for (final device in devices) {
      if (device.userId != userId) {
        throw FormatException('device record ${device.deviceUuid} has userId ${device.userId} but the file belongs to $userId');
      }
      if (!seen.add(device.deviceUuid)) {
        throw FormatException('duplicate deviceUuid ${device.deviceUuid} in $fileKey');
      }
    }
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('missing or invalid "$key" (expected a string)');
  }
  return value;
}

Hlc _hlc(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('missing or invalid "$key" (expected an HLC key string)');
  }
  try {
    return Hlc.fromKey(value);
  } on FormatException catch (e) {
    throw FormatException('invalid "$key": $e');
  }
}

Map<String, dynamic> _recordMap(Object? entry, String what) {
  if (entry is! Map) {
    throw FormatException('each $what must be a JSON object');
  }
  return Map<String, dynamic>.from(entry);
}
