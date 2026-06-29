// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

final class DeviceIdentity {
  final String uuid;
  final String name;
  final DateTime createdAt;
  final String? lastHlc;
  final String? publicKey;

  const DeviceIdentity({
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.lastHlc,
    this.publicKey,
  });

  String get truncatedDeviceId => uuid.replaceAll('-', '').substring(0, 8);

  DeviceIdentity withLastHlc(String hlcKey) => DeviceIdentity(
    uuid: uuid,
    name: name,
    createdAt: createdAt,
    lastHlc: hlcKey,
    publicKey: publicKey,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'last_hlc': lastHlc,
    'public_key': publicKey,
  };

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
    uuid: json['uuid'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    lastHlc: json['last_hlc'] as String?,
    publicKey: json['public_key'] as String?,
  );
}
