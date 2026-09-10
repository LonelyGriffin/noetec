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

  group('CryptoServiceImpl.sign / verify —', () {
    late String pubKey;
    late String privKey;

    setUp(() async {
      final pair = await service.deriveIdentityKeyPair(entropy32);
      pubKey = pair.publicKeyBase64Url;
      privKey = pair.privateKeyBase64Url;
    });

    test('round-trips: sign then verify succeeds', () async {
      final bytes = utf8.encode('hello, world');
      final sig = await service.sign(privKey, bytes);

      expect(await service.verify(pubKey, bytes, sig), isTrue, reason: 'a genuine signature must verify under its own key');
    });

    test('a tampered input fails verification', () async {
      final bytes = utf8.encode('hello, world');
      final sig = await service.sign(privKey, bytes);

      final tampered = List<int>.from(bytes)..[0] ^= 0x01;
      expect(await service.verify(pubKey, tampered, sig), isFalse, reason: 'a signature over a different byte string must not verify');
    });

    test('a signature verifies under the correct key only', () async {
      final bytes = utf8.encode('hello, world');
      final sig = await service.sign(privKey, bytes);

      // A different key (different entropy) must not verify the signature.
      final otherEntropy = List<int>.from(entropy32)..[0] ^= 0xff;
      final other = await service.deriveIdentityKeyPair(otherEntropy);

      expect(await service.verify(other.publicKeyBase64Url, bytes, sig), isFalse, reason: 'a signature must not verify under a different public key');
    });

    test('rejects a malformed signature (wrong length) with false', () async {
      final bytes = utf8.encode('hello, world');
      final sig = await service.sign(privKey, bytes);
      // Chop one base64url char off the signature.
      expect(await service.verify(pubKey, bytes, sig.substring(0, sig.length - 1)), isFalse);
    });

    test('signature is base64url (no +, /, or =) and 64 bytes', () async {
      final bytes = utf8.encode('hello, world');
      final sig = await service.sign(privKey, bytes);

      expect(sig.contains('+'), isFalse);
      expect(sig.contains('/'), isFalse);
      expect(sig.contains('='), isFalse);
      expect(base64UrlDecode(sig).length, 64);
    });

    test('sign throws ArgumentError for a non-32-byte seed', () {
      expect(() => service.sign(base64UrlEncodeNoPad([1, 2, 3]), <int>[1]), throwsArgumentError);
    });
  });

  group('base64url helpers —', () {
    test('encode/decode round-trip', () {
      final bytes = List<int>.generate(33, (i) => (i * 7) % 251);
      final encoded = base64UrlEncodeNoPad(bytes);
      expect(encoded.contains('='), isFalse);
      expect(base64UrlDecode(encoded), bytes);
    });

    test('decodes a legacy padded standard-base64 value', () {
      // 32 bytes → standard base64 with one '=' pad char.
      final bytes = List<int>.generate(32, (i) => i + 1);
      final legacy = base64Encode(Uint8List.fromList(bytes));
      expect(legacy.contains('='), isTrue);
      expect(base64UrlDecode(legacy), bytes);
    });

    test('decodes legacy base64 using + / alphabet', () {
      // 0xFB 0xFF 0xFF … encodes to '+//…' in standard base64 and '-__…' in
      // base64url. Both must decode to the same bytes.
      final bytes = <int>[0xFB, 0xFF, 0xFF, 0xFE, 0xFF, 0xFF];
      final legacy = base64Encode(bytes);
      final url = base64UrlEncodeNoPad(bytes);
      expect(legacy.contains('+'), isTrue);
      expect(base64UrlDecode(legacy), bytes);
      expect(base64UrlDecode(url), bytes);
    });
  });

  group('CryptoServiceImpl.generateDeviceKeyPair — sign→verify round-trip (NOET-28)', () {
    test('a device key can sign and its public key can verify', () async {
      final pair = await service.generateDeviceKeyPair();

      final bytes = utf8.encode('oplog entry signing input');
      final sig = await service.sign(pair.privateKeyBase64Url, bytes);

      expect(await service.verify(pair.publicKeyBase64Url, bytes, sig), isTrue, reason: 'a genuine device-key signature must verify under its own public key');
    });

    test('a device-key signature does not verify under a different key', () async {
      final pair = await service.generateDeviceKeyPair();
      final other = await service.generateDeviceKeyPair();

      final bytes = utf8.encode('oplog entry signing input');
      final sig = await service.sign(pair.privateKeyBase64Url, bytes);

      expect(await service.verify(other.publicKeyBase64Url, bytes, sig), isFalse, reason: 'a signature must not verify under another device key');
    });

    test('device keys are independent across generations (not derived from the identity seed)', () async {
      final a = await service.generateDeviceKeyPair();
      final b = await service.generateDeviceKeyPair();
      expect(a.publicKeyBase64Url, isNot(b.publicKeyBase64Url));
    });
  });

  group('normalizeToBase64Url (sync-security.md §2.1 encoding migration) —', () {
    test('re-encodes a legacy padded standard-base64 value to base64url no-pad', () {
      final bytes = List<int>.generate(32, (i) => (i * 13) % 251);
      final legacy = base64Encode(Uint8List.fromList(bytes));
      expect(legacy.contains('='), isTrue, reason: 'precondition: padded legacy form');

      final normalized = normalizeToBase64Url(legacy);
      expect(normalized.contains('='), isFalse);
      expect(normalized.contains('+'), isFalse);
      expect(normalized.contains('/'), isFalse);
      expect(base64UrlDecode(normalized), bytes);
      expect(normalized, base64UrlEncodeNoPad(bytes));
    });

    test('leaves an already-base64url no-pad value unchanged', () {
      final bytes = List<int>.generate(32, (i) => (i * 7) % 251);
      final url = base64UrlEncodeNoPad(bytes);
      expect(normalizeToBase64Url(url), url);
    });
  });
}
