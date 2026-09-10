// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'file_system_service.dart';

/// The outcome of a TOFU key observation (sync-security.md §5.2).
sealed class TrustDecision {
  const TrustDecision();
}

/// First observation: [key] was not in the trust store and is now pinned
/// and trusted (§5.2 rule 1).
final class TrustPinned extends TrustDecision {
  const TrustPinned({required this.key});

  final String key;
}

/// The observed [key] equals the stored key: the key verifies normally
/// (§5.2 rule 2).
final class TrustVerified extends TrustDecision {
  const TrustVerified({required this.key});

  final String key;
}

/// Key substitution: the stored key is [storedKey] but [observedKey] was
/// observed (file-replacement attack, or a device/user that lost its key).
/// The stored key stays authoritative, the mismatch MUST be reported to the
/// user with both keys, and only [ITrustStore.confirmKey] may adopt
/// [observedKey] (§5.2 rule 3, §9).
final class TrustSubstituted extends TrustDecision {
  const TrustSubstituted({required this.storedKey, required this.observedKey});

  final String storedKey;
  final String observedKey;
}

/// Trust-on-first-use (TOFU) key store (sync-security.md §5).
///
/// Pins device and identity public keys in `.noetec/trusted_keys.json`
/// (per-device local state that MUST NOT be synced or shared between vaults,
/// §5.3) and detects key substitution: an observed key different from the
/// stored one is rejected and reported via `package:logging` until the user
/// explicitly confirms it (§5.2 rule 3).
abstract interface class ITrustStore {
  /// Observes [publicKeyBase64Url] under [identifier] (a `deviceUuid` or a
  /// `userId`) for the vault at [vaultRootPath].
  ///
  /// - Key not stored → it is pinned (first observation is trusted) and
  ///   persisted.
  /// - Key equal to the stored one → verifies normally.
  /// - Key different from the stored one → key substitution: the stored key
  ///   stays authoritative, the mismatch is logged, and
  ///   [confirmKey] is required to adopt the new key.
  Future<TrustDecision> observeKey(String vaultRootPath, String identifier, String publicKeyBase64Url);

  /// Adopts [publicKeyBase64Url] as the trusted key for [identifier] after
  /// the user confirmed a key substitution (§5.2 rule 3).
  ///
  /// Throws [ArgumentError] if [identifier] was never pinned.
  Future<void> confirmKey(String vaultRootPath, String identifier, String publicKeyBase64Url);

  /// Resets the trust store, re-arming first-observation trust (§5.3).
  Future<void> reset(String vaultRootPath);

  /// The currently pinned keys, for diagnostics (UI: NOET-33).
  Future<Map<String, String>> pinnedKeys(String vaultRootPath);
}

class TrustStoreImpl implements ITrustStore {
  TrustStoreImpl(this._fileSystem);

  final IFileSystemService _fileSystem;
  final Logger _logger = Logger('trust_store');
  final Map<String, Future<void>> _vaultLocks = {};

  /// `.noetec/trusted_keys.json` — deliberately outside the syncable
  /// `.sync/` area (§5.1).
  String _storePath(String vaultRootPath) => p.join(vaultRootPath, '.noetec', 'trusted_keys.json');

  @override
  Future<TrustDecision> observeKey(String vaultRootPath, String identifier, String publicKeyBase64Url) => _withVaultLock(vaultRootPath, () async {
    final store = await _loadStore(vaultRootPath);
    final stored = store[identifier];

    if (stored == null) {
      store[identifier] = publicKeyBase64Url;
      await _saveStore(vaultRootPath, store);
      _logger.info('TOFU: pinned first observed key for $identifier');
      return TrustPinned(key: publicKeyBase64Url);
    }
    if (stored == publicKeyBase64Url) {
      return TrustVerified(key: stored);
    }

    _logger.warning(
      'TOFU key substitution detected for $identifier — stored: $stored, observed: $publicKeyBase64Url. '
      'The stored key stays authoritative until the user confirms the new key.',
    );
    return TrustSubstituted(storedKey: stored, observedKey: publicKeyBase64Url);
  });

  @override
  Future<void> confirmKey(String vaultRootPath, String identifier, String publicKeyBase64Url) => _withVaultLock(vaultRootPath, () async {
    final store = await _loadStore(vaultRootPath);
    if (!store.containsKey(identifier)) {
      throw ArgumentError.value(identifier, 'identifier', 'Cannot confirm a key substitution for an identifier that was never pinned');
    }
    store[identifier] = publicKeyBase64Url;
    await _saveStore(vaultRootPath, store);
    _logger.info('TOFU: user confirmed a new key for $identifier');
  });

  @override
  Future<void> reset(String vaultRootPath) => _withVaultLock(vaultRootPath, () async {
    final path = _storePath(vaultRootPath);
    if (await _fileSystem.fileExists(path)) {
      await _fileSystem.deleteFile(path);
      _logger.info('TOFU trust store reset — first-observation trust re-armed');
    }
  });

  @override
  Future<Map<String, String>> pinnedKeys(String vaultRootPath) => _withVaultLock(vaultRootPath, () async {
    final store = await _loadStore(vaultRootPath);
    return Map.unmodifiable(store);
  });

  /// Reads and decodes `trusted_keys.json`; a missing file yields an empty
  /// store (§8.4). A malformed file (not a JSON object, or entries that are
  /// not string→string pairs) throws [FormatException] rather than being
  /// silently re-armed — a silently reset store would re-trust an attacker's
  /// first observation.
  Future<Map<String, String>> _loadStore(String vaultRootPath) async {
    final path = _storePath(vaultRootPath);
    if (!await _fileSystem.fileExists(path)) return {};

    final decoded = jsonDecode(await _fileSystem.readFile(path));
    if (decoded is! Map) {
      throw FormatException('trusted_keys.json must contain a single JSON object, got ${decoded.runtimeType}');
    }
    final store = <String, String>{};
    decoded.forEach((key, value) {
      if (key is! String || value is! String) {
        throw FormatException('trusted_keys.json entries must be "identifier" -> "base64url key" string pairs; invalid entry: $key');
      }
      store[key] = value;
    });
    return store;
  }

  Future<void> _saveStore(String vaultRootPath, Map<String, String> store) async {
    final noetecDir = p.join(vaultRootPath, '.noetec');
    if (!await _fileSystem.directoryExists(noetecDir)) {
      await _fileSystem.createDirectory(noetecDir);
    }
    await _fileSystem.writeFile(_storePath(vaultRootPath), jsonEncode(store));
  }

  /// Serializes read-modify-write cycles per vault: the file store has no
  /// atomicity, so concurrent observations (e.g. several device files in one
  /// sync cycle) must not lose a pin.
  ///
  /// The new head is registered **synchronously, before** awaiting the
  /// predecessor, so every waiter in the same burst chains onto the most
  /// recent one and the actions run strictly one at a time. (Registering the
  /// head *after* the await lets every waiter capture the same predecessor
  /// and then resume together — interleaving their read-modify-write cycles.)
  Future<T> _withVaultLock<T>(String vaultRootPath, Future<T> Function() action) async {
    final previous = _vaultLocks[vaultRootPath];
    final owner = Completer<void>();
    _vaultLocks[vaultRootPath] = owner.future; // new head first
    try {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // The previous operation reports its own failure; do not cascade it
          // into unrelated observations.
        }
      }
      return await action();
    } finally {
      owner.complete();
    }
  }
}
