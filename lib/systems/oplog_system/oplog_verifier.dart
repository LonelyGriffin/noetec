// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';
import 'package:logging/logging.dart';

import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';

/// Verifies OpLog entries on read (sync-security.md §2.4) and applies
/// **chain rejection** (§2.4.3): a signature failure — or an entry that is
/// structurally unverifiable — rejects that entry **and every subsequent entry
/// in the same device file**; earlier valid entries are kept.
///
/// Legacy (unsigned) entries (§8.1) are accepted during migration and do **not**
/// start a chain rejection. A file may therefore mix legacy and signed entries;
/// the first signed entry is verified against the file's first-entry `pubKey`
/// (or, when the file carries no `pubKey`, against [keyResolver]).
///
/// Rejected entries are reported via [package:logging] (never `print`), per
/// §9.
class OpLogVerifier {
  OpLogVerifier({required ICryptoService crypto, required OpLogSerializer serializer, this.keyResolver}) : _crypto = crypto, _serializer = serializer;

  final ICryptoService _crypto;
  final OpLogSerializer _serializer;

  /// Resolves the authoring device's base64url public key for a device file
  /// that carries **no** `pubKey` on any entry — i.e. a mixed legacy/signed
  /// file whose legacy first entry predates Phase 1. For the local device this
  /// is the key in `device.json`; for remote devices it is `null` in Phase 1
  /// (remote key trust is deferred to the Phase-4 TOFU store, NOET-30).
  ///
  /// When a signed entry cannot be resolved to any key it is structurally
  /// unverifiable and triggers chain rejection.
  final FutureOr<String?> Function(String deviceId)? keyResolver;

  static final Logger _log = Logger('OpLogVerifier');

  /// Verifies [entries] (one device file, in file order) for the page at
  /// [relativePath] and returns the accepted prefix.
  ///
  /// The returned list preserves file order. It is empty if the first entry
  /// is rejected, and it is the full list when no entry is rejected.
  Future<List<OpLogEntry>> verifyFile(String relativePath, List<OpLogEntry> entries) async {
    final documentPath = documentPathFromRelativePath(relativePath);
    final accepted = <OpLogEntry>[];

    String? deviceKey;
    for (final entry in entries) {
      // Capture the first pubKey in file order as the device key. In a
      // well-formed file this is the first entry (no parent); in a mixed file
      // it is the first signed entry.
      if (deviceKey == null && entry.pubKey != null) {
        deviceKey = entry.pubKey;
      }

      if (entry.signature == null) {
        // Legacy (unsigned) entry — accepted, never starts chain rejection.
        accepted.add(entry);
        continue;
      }

      // Signed entry: resolve the verifying key.
      final key = deviceKey ?? (keyResolver != null ? await keyResolver!(entry.deviceId) : null);
      if (key == null) {
        _log.warning('OpLog entry ${entry.hlcKey} at $relativePath (device ${entry.deviceId}) is signed but no public key is available — rejecting it and the rest of the chain');
        break;
      }

      final input = _serializer.signingInput(entry, documentPath);
      final ok = await _crypto.verify(key, input, entry.signature!);
      if (!ok) {
        _log.warning('Signature verification failed for OpLog entry ${entry.hlcKey} at $relativePath (device ${entry.deviceId}) — rejecting it and the rest of the chain');
        break;
      }

      accepted.add(entry);
    }

    return accepted;
  }
}
