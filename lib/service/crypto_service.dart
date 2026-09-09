// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encodes [bytes] as base64url (RFC 4648 §5) **without** `=` padding.
///
/// sync-security.md §2.1: public keys are base64url with no padding.
String base64UrlEncodeNoPad(List<int> bytes) => base64Url.encode(Uint8List.fromList(bytes)).replaceAll('=', '');

/// Decodes a base64url (RFC 4648 §5) string, re-adding `=` padding if the
/// encoder stripped it.
List<int> base64UrlDecode(String value) {
  final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(padded);
}

/// A derived Ed25519 identity key pair.
///
/// [publicKeyBase64Url] is base64url (RFC 4648 §5, no padding) — the form
/// required by sync-security.md §2.1. [privateKeyBase64Url] is the 32-byte
/// Ed25519 secret seed, base64url, and must be kept only in secure storage.
final class IdentityKeyPair {
  const IdentityKeyPair({required this.publicKeyBase64Url, required this.privateKeyBase64Url});

  final String publicKeyBase64Url;
  final String privateKeyBase64Url;
}

abstract interface class ICryptoService {
  Future<({String publicKeyBase64, String privateKeyBase64})> generateDeviceKeyPair();

  /// Derives the Ed25519 identity key pair deterministically from a 32-byte
  /// entropy seed (ADR-0007 §1).
  ///
  /// HKDF-SHA256 (RFC 5869) with `salt = "noetec.identity.v1"` and
  /// `info = "noetec-identity-key"` produces the 32-byte Ed25519 seed; the
  /// public key is then base64url-encoded (no padding). The same entropy
  /// always yields the same identity key.
  Future<IdentityKeyPair> deriveIdentityKeyPair(List<int> entropy32);
}

class CryptoServiceImpl implements ICryptoService {
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<({String publicKeyBase64, String privateKeyBase64})> generateDeviceKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final publicKeyBytes = publicKey.bytes;
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    return (publicKeyBase64: base64Encode(Uint8List.fromList(publicKeyBytes)), privateKeyBase64: base64Encode(Uint8List.fromList(privateKeyBytes)));
  }

  @override
  Future<IdentityKeyPair> deriveIdentityKeyPair(List<int> entropy32) async {
    if (entropy32.length != 32) {
      throw ArgumentError.value(entropy32.length, 'entropy32', 'Identity entropy MUST be 32 bytes');
    }

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final edSeed = await hkdf.deriveKey(secretKey: SecretKey(Uint8List.fromList(entropy32)), nonce: utf8.encode('noetec.identity.v1'), info: utf8.encode('noetec-identity-key'));

    final keyPair = await _algorithm.newKeyPairFromSeed(edSeed.bytes);
    final publicKeyBytes = (await keyPair.extractPublicKey()).bytes;

    return IdentityKeyPair(publicKeyBase64Url: base64UrlEncodeNoPad(publicKeyBytes), privateKeyBase64Url: base64UrlEncodeNoPad(edSeed.bytes));
  }
}
