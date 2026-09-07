// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Local, non-synced user identity (ADR-0007 §1, sync-security.md §2.1).
///
/// Mirrors [DeviceIdentity] (../device/device_identity.dart): the identity is
/// an Ed25519 key pair derived deterministically from a 32-byte entropy seed
/// (backed up as a BIP39 mnemonic).
///
/// Only **public** fields are serialized here — the entropy seed and the
/// identity private key live solely in flutter_secure_storage (via
/// `ISecureKeyStore`) and MUST NOT be written to the vault.
final class UserIdentity {
  final String userId;
  final String name;
  final String publicKey;
  final String role;

  const UserIdentity({
    required this.userId,
    required this.name,
    required this.publicKey,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'publicKey': publicKey,
    'role': role,
  };

  factory UserIdentity.fromJson(Map<String, dynamic> json) => UserIdentity(
    userId: json['userId'] as String,
    name: json['name'] as String,
    publicKey: json['publicKey'] as String,
    role: json['role'] as String,
  );
}
