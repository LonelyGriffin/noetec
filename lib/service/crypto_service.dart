// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encodes [bytes] as base64url (RFC 4648 §5) **without** `=` padding.
///
/// sync-security.md §2.1: public keys, signatures, and all other wire values
/// are base64url with no padding.
String base64UrlEncodeNoPad(List<int> bytes) => base64Url.encode(Uint8List.fromList(bytes)).replaceAll('=', '');

/// Decodes a base64 or base64url encoded value to bytes.
///
/// Accepts both base64url (RFC 4648 §5, `-`/`_`, with or without `=` padding)
/// and standard base64 (RFC 4648 §4, `+`/`/`, `=` padding) so that legacy
/// `device.json` values (padded standard base64) can still be read — see
/// sync-security.md §2.1 "Encoding migration". Throws [FormatException] if the
/// input is not valid base64.
List<int> base64UrlDecode(String value) {
  final normalized = value.trim().replaceAll('-', '+').replaceAll('_', '/');
  final padCount = (4 - normalized.length % 4) % 4;
  final padded = normalized.padRight(normalized.length + padCount, '=');
  return base64Decode(padded);
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
  /// Generates a fresh Ed25519 device key pair.
  ///
  /// Both keys are base64url-encoded (no padding), per sync-security.md §2.1.
  Future<({String publicKeyBase64Url, String privateKeyBase64Url})> generateDeviceKeyPair();

  /// Derives the Ed25519 identity key pair deterministically from a 32-byte
  /// entropy seed (ADR-0007 §1).
  ///
  /// HKDF-SHA256 (RFC 5869) with `salt = "noetec.identity.v1"` and
  /// `info = "noetec-identity-key"` produces the 32-byte Ed25519 seed; the
  /// public key is then base64url-encoded (no padding). The same entropy
  /// always yields the same identity key.
  Future<IdentityKeyPair> deriveIdentityKeyPair(List<int> entropy32);

  /// Signs [bytes] with the Ed25519 secret seed [privateKeyBase64Url]
  /// (32 bytes, base64url no padding) and returns the 64-byte signature
  /// encoded as base64url (no padding).
  ///
  /// Throws [ArgumentError] if the seed is not exactly 32 bytes, and
  /// [FormatException] if the seed is not valid base64.
  Future<String> sign(String privateKeyBase64Url, List<int> bytes);

  /// Verifies that [signatureBase64Url] (base64url no padding) is a valid
  /// Ed25519 signature over [bytes] under the 32-byte public key
  /// [publicKeyBase64Url] (base64url no padding).
  ///
  /// Returns `false` for a wrong key, a malformed key or signature, or an
  /// invalid signature; it never throws for a verification failure.
  Future<bool> verify(String publicKeyBase64Url, List<int> bytes, String signatureBase64Url);
}

class CryptoServiceImpl implements ICryptoService {
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<({String publicKeyBase64Url, String privateKeyBase64Url})> generateDeviceKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final publicKeyBytes = publicKey.bytes;
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    return (publicKeyBase64Url: base64UrlEncodeNoPad(publicKeyBytes), privateKeyBase64Url: base64UrlEncodeNoPad(privateKeyBytes));
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

  @override
  Future<String> sign(String privateKeyBase64Url, List<int> bytes) async {
    final seed = base64UrlDecode(privateKeyBase64Url);
    if (seed.length != 32) {
      throw ArgumentError.value(seed.length, 'privateKeyBase64Url', 'Ed25519 secret seed MUST be 32 bytes');
    }

    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final signature = await _algorithm.sign(bytes, keyPair: keyPair);
    return base64UrlEncodeNoPad(signature.bytes);
  }

  @override
  Future<bool> verify(String publicKeyBase64Url, List<int> bytes, String signatureBase64Url) async {
    final List<int> publicKeyBytes;
    final List<int> signatureBytes;
    try {
      publicKeyBytes = base64UrlDecode(publicKeyBase64Url);
      signatureBytes = base64UrlDecode(signatureBase64Url);
    } on FormatException {
      return false;
    }

    if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
      return false;
    }

    final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
    final signature = Signature(signatureBytes, publicKey: publicKey);
    return await _algorithm.verify(bytes, signature: signature);
  }
}
