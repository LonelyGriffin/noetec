// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:logging/logging.dart';

import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';

/// Normalizes a page `relativePath` (e.g. `pages/notes/ideas.md`) to the
/// `documentPath` used in the Phase-1 signing input (sync-security.md §2.2):
/// the path relative to the vault root with the `.md` extension stripped and
/// `/` separators (e.g. `notes/ideas`).
///
/// This is a pure string transform (no filesystem, no locale) so the bytes are
/// byte-identical across devices — a hard requirement of the signing input.
String documentPathFromRelativePath(String relativePath) {
  var path = relativePath.replaceAll('\\', '/');
  if (path.endsWith('.md')) {
    path = path.substring(0, path.length - '.md'.length);
  }
  return path;
}

/// Signs OpLog entries on write with the authoring device's Ed25519 key.
///
/// sync-security.md §2.2–2.3:
/// - `signature` = base64url Ed25519 over
///   `canonicalJson(entryWithoutSignature) + documentPath`, where the entry is
///   serialized as its **wire** representation (snake_case keys) — never the
///   Dart model — so the signed bytes are byte-identical across devices.
/// - `pubKey` (base64url) is present **only** on the first entry (the entry
///   with no `parent`) and is normalized to base64url (legacy padded keys are
///   re-encoded per §2.1 "Encoding migration"); it is omitted on later entries.
///
/// Legacy handling (§8.1): a device whose private key is not in secure storage
/// (e.g. a device created before the key store existed) cannot sign, so it
/// writes the entry in pure legacy form — no `signature`, no `pubKey`. Legacy
/// entries are accepted on read and do not start chain rejection. A warning is
/// logged (never `print`).
class OpLogSigner {
  OpLogSigner({required ICryptoService crypto, required ISecureKeyStore secureKeyStore, required OpLogSerializer serializer})
    : _crypto = crypto,
      _secureKeyStore = secureKeyStore,
      _serializer = serializer;

  final ICryptoService _crypto;
  final ISecureKeyStore _secureKeyStore;
  final OpLogSerializer _serializer;
  static final Logger _log = Logger('OpLogSigner');

  /// Signs [entry] for [relativePath] (the page path used as the OpLog
  /// directory) and returns the signed entry.
  ///
  /// [vaultId] keys the secure key store lookup for the device private key.
  /// [devicePublicKeyBase64Url] is the authoring device's public key (from
  /// `device.json`) — placed on `pubKey` (base64url-normalized) only when
  /// [entry] is the first entry of the device file (no `parent`).
  Future<OpLogEntry> sign(OpLogEntry entry, String relativePath, {required String vaultId, required String devicePublicKeyBase64Url}) async {
    final privateKey = await _secureKeyStore.readDevicePrivateKey(vaultId);
    if (privateKey == null) {
      _log.warning('No device private key in secure storage for vault $vaultId — OpLog entry ${entry.hlcKey} at $relativePath written unsigned (legacy form)');
      return entry.withSignature(signature: null, pubKey: null);
    }

    // Build the entry with `pubKey` set first. Per §2.2 the signature is over
    // `entryWithoutSignature`, which includes `pubKey` ("all other keys,
    // including pubKey, MUST be present exactly as serialized"). Signing this
    // form makes the signed bytes identical to what the verifier reconstructs
    // from the decoded wire entry.
    final isFirst = entry.parent == null;
    final pubKey = isFirst ? normalizeToBase64Url(devicePublicKeyBase64Url) : null;
    final unsigned = entry.withSignature(signature: null, pubKey: pubKey);

    final documentPath = documentPathFromRelativePath(relativePath);
    final input = _serializer.signingInput(unsigned, documentPath);
    final signature = await _crypto.sign(privateKey, input);

    return unsigned.withSignature(signature: signature, pubKey: pubKey);
  }
}
