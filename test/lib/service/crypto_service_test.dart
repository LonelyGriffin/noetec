// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/crypto_service.dart';

/// Reference HKDF-SHA256 (RFC 5869) implemented with `package:crypto`'s HMAC,
/// independent of `package:cryptography`, to cross-validate the derivation.
Uint8List hkdfSha256Reference(List<int> ikm, List<int> salt, List<int> info, int length) {
  final prk = crypto.Hmac(crypto.sha256, salt).convert(ikm).bytes;
  var t = <int>[];
  final okm = <int>[];
  for (var i = 1; okm.length < length; i++) {
    final mac = crypto.Hmac(crypto.sha256, prk).convert([...t, ...info, i]);
    t = mac.bytes;
    okm.addAll(t);
  }
  return Uint8List.fromList(okm.sublist(0, length));
}

void main() {
  final service = CryptoServiceImpl();

  final entropy32 = Uint8List.fromList(List.generate(32, (i) => i));

  group('CryptoServiceImpl.deriveIdentityKeyPair —', () {
    test('derives the Ed25519 seed via HKDF-SHA256 (ADR-0007 §1)', () async {
      final pair = await service.deriveIdentityKeyPair(entropy32);

      final expectedSeed = hkdfSha256Reference(entropy32, utf8.encode('noetec.identity.v1'), utf8.encode('noetec-identity-key'), 32);
      final actualSeed = base64UrlDecode(pair.privateKeyBase64Url);

      expect(actualSeed, expectedSeed);
    });

    test('is deterministic: same entropy → same key pair', () async {
      final a = await service.deriveIdentityKeyPair(entropy32);
      final b = await service.deriveIdentityKeyPair(Uint8List.fromList(entropy32));

      expect(a.publicKeyBase64Url, b.publicKeyBase64Url);
      expect(a.privateKeyBase64Url, b.privateKeyBase64Url);
    });

    test('different entropy → different key pair', () async {
      final a = await service.deriveIdentityKeyPair(entropy32);
      final other = List<int>.from(entropy32)..[0] ^= 0xff;
      final b = await service.deriveIdentityKeyPair(other);

      expect(a.publicKeyBase64Url, isNot(b.publicKeyBase64Url));
      expect(a.privateKeyBase64Url, isNot(b.privateKeyBase64Url));
    });

    test('encodes both keys as base64url (no +, /, or =)', () async {
      final pair = await service.deriveIdentityKeyPair(entropy32);

      for (final value in [pair.publicKeyBase64Url, pair.privateKeyBase64Url]) {
        expect(value.contains('+'), isFalse);
        expect(value.contains('/'), isFalse);
        expect(value.contains('='), isFalse);
      }
    });

    test('public and private keys are 32 bytes', () async {
      final pair = await service.deriveIdentityKeyPair(entropy32);

      expect(base64UrlDecode(pair.publicKeyBase64Url).length, 32);
      expect(base64UrlDecode(pair.privateKeyBase64Url).length, 32);
    });

    test('rejects entropy that is not 32 bytes', () {
      expect(() => service.deriveIdentityKeyPair(<int>[1, 2, 3]), throwsArgumentError);
    });
  });
}
