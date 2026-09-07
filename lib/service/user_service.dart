// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;

import '../entity/user/user_identity.dart';
import 'crypto_service.dart';
import 'file_system_service.dart';
import 'id_service.dart';
import 'secure_key_store.dart';

/// A freshly created user identity.
///
/// [mnemonic] is the 24-word BIP39 backup of the 32-byte entropy seed. It is
/// shown once at creation for backup (ADR-0007 §2) and is also persisted in
/// secure storage so the identity can be restored on other devices.
final class CreatedIdentity {
  const CreatedIdentity({required this.identity, required this.mnemonic});

  final UserIdentity identity;

  /// 24-word BIP39 mnemonic (backup of the 32-byte entropy seed).
  final String mnemonic;
}

/// Manages the local user identity for a vault (ADR-0007).
///
/// Responsibilities:
/// - Create an identity: 32 random bytes → 24-word BIP39 mnemonic (backup) →
///   HKDF-SHA256 → Ed25519 identity key pair.
/// - Restore an identity from a BIP39 mnemonic (deterministic — yields the
///   same identity key as creation).
/// - Persist the public identity to `.noetec/identity.json` (non-synced).
/// - Keep the seed and identity private key in flutter_secure_storage only.
abstract interface class IUserService {
  /// The identity currently loaded for the active vault, if any.
  UserIdentity? get currentIdentity;

  /// Creates a new identity for [vaultRootPath].
  ///
  /// Generates 32 random bytes, derives the BIP39 mnemonic and the Ed25519
  /// key pair, persists the public identity and stores the secrets.
  Future<CreatedIdentity> createIdentity(
    String vaultRootPath,
    String vaultId, {
    String name = 'Default User',
    String role = 'owner',
  });

  /// Restores an identity from a 24-word BIP39 [mnemonic].
  ///
  /// Deterministic: the same mnemonic always yields the same identity key.
  /// [userId] (when omitted) is read from an existing `identity.json`, else
  /// a fresh UUID is generated.
  Future<UserIdentity> restoreIdentity(
    String vaultRootPath,
    String vaultId,
    String mnemonic, {
    String? userId,
  });

  /// Loads the identity from `.noetec/identity.json` if present.
  Future<UserIdentity?> loadIdentity(String vaultRootPath);

  /// Clears the in-memory identity.
  void clear();
}

class UserServiceImpl implements IUserService {
  final IFileSystemService _fileSystem;
  final IIdService _idService;
  final ICryptoService _cryptoService;
  final ISecureKeyStore _secureKeyStore;
  final Random _random;
  UserIdentity? _currentIdentity;

  UserServiceImpl(
    this._fileSystem,
    this._idService,
    this._cryptoService,
    this._secureKeyStore, {
    Random? random,
  }) : _random = random ?? Random.secure();

  @override
  UserIdentity? get currentIdentity => _currentIdentity;

  String _identityPath(String vaultRootPath) =>
      '$vaultRootPath/.noetec/identity.json';

  /// Converts a lowercase hex string (as returned by `bip39.mnemonicToEntropy`)
  /// into its byte representation.
  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Uint8List _randomEntropy() {
    final entropy = Uint8List(32);
    for (var i = 0; i < entropy.length; i++) {
      entropy[i] = _random.nextInt(256);
    }
    return entropy;
  }

  @override
  Future<CreatedIdentity> createIdentity(
    String vaultRootPath,
    String vaultId, {
    String name = 'Default User',
    String role = 'owner',
  }) async {
    final entropy = _randomEntropy();
    final mnemonic = bip39.entropyToMnemonic(
      entropy.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    final identity = await _persistIdentity(
      vaultRootPath,
      vaultId,
      entropy: entropy,
      userId: _idService.generateId(),
      name: name,
      role: role,
    );
    return CreatedIdentity(identity: identity, mnemonic: mnemonic);
  }

  @override
  Future<UserIdentity> restoreIdentity(
    String vaultRootPath,
    String vaultId,
    String mnemonic, {
    String? userId,
  }) async {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw ArgumentError.value(mnemonic, 'mnemonic', 'Invalid BIP39 mnemonic');
    }
    final entropy = _hexToBytes(bip39.mnemonicToEntropy(mnemonic));

    final existing = await loadIdentity(vaultRootPath);
    final resolvedUserId =
        userId ?? existing?.userId ?? _idService.generateId();
    return _persistIdentity(
      vaultRootPath,
      vaultId,
      entropy: entropy,
      userId: resolvedUserId,
      name: existing?.name ?? 'Restored User',
      role: existing?.role ?? 'owner',
    );
  }

  /// Derives the key pair from [entropy], stores the secrets, and writes
  /// `.noetec/identity.json`.
  Future<UserIdentity> _persistIdentity(
    String vaultRootPath,
    String vaultId, {
    required Uint8List entropy,
    required String userId,
    required String name,
    required String role,
  }) async {
    final seedBase64Url = base64UrlEncodeNoPad(entropy);
    final keyPair = await _cryptoService.deriveIdentityKeyPair(entropy);

    await _secureKeyStore.storeIdentitySeed(vaultId, seedBase64Url);
    await _secureKeyStore.storeIdentityPrivateKey(
      vaultId,
      keyPair.privateKeyBase64Url,
    );

    final identity = UserIdentity(
      userId: userId,
      name: name,
      publicKey: keyPair.publicKeyBase64Url,
      role: role,
    );

    if (!await _fileSystem.directoryExists('$vaultRootPath/.noetec')) {
      await _fileSystem.createDirectory('$vaultRootPath/.noetec');
    }
    await _fileSystem.writeFile(
      _identityPath(vaultRootPath),
      jsonEncode(identity.toJson()),
    );

    _currentIdentity = identity;
    return identity;
  }

  @override
  Future<UserIdentity?> loadIdentity(String vaultRootPath) async {
    final path = _identityPath(vaultRootPath);
    if (!await _fileSystem.fileExists(path)) return null;
    final content = await _fileSystem.readFile(path);
    return UserIdentity.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  @override
  void clear() {
    _currentIdentity = null;
  }
}
