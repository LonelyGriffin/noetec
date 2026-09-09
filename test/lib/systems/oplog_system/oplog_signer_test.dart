// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';

import '../../../helpers/test_fakes.dart';

OpLogEntry _entry({required Hlc hlc, Hlc? parent, required OpEntryType type, required String deviceId, List<BlockOp>? blockOps}) =>
    OpLogEntry(version: 1, hlc: hlc, parent: parent, parentB: null, type: type, blockOps: blockOps, fileOp: null, fileHash: null, deviceId: deviceId);

void main() {
  const serializer = OpLogSerializer();
  final crypto = CryptoServiceImpl();

  group('documentPathFromRelativePath (§2.2 signing input) —', () {
    test('strips the .md extension and normalizes separators', () {
      expect(documentPathFromRelativePath('pages/notes/ideas.md'), 'pages/notes/ideas');
      expect(documentPathFromRelativePath(r'pages\notes\ideas.md'), 'pages/notes/ideas');
      expect(documentPathFromRelativePath('notes/ideas.md'), 'notes/ideas');
    });

    test('keeps a path that has no .md extension unchanged', () {
      expect(documentPathFromRelativePath('pages/ideas'), 'pages/ideas');
    });
  });

  group('OpLogSigner.sign —', () {
    late FakeSecureKeyStore store;
    late OpLogSigner signer;
    late String pubKey;
    late String privKey;

    const deviceId = 'dev1-uuid-here-xxxx-xxxxxxxxxxxx';
    const vaultId = 'vault-1';

    setUp(() async {
      store = FakeSecureKeyStore();
      signer = OpLogSigner(crypto: crypto, secureKeyStore: store, serializer: serializer);
      final pair = await crypto.generateDeviceKeyPair();
      pubKey = pair.publicKeyBase64Url;
      privKey = pair.privateKeyBase64Url;
      await store.storeDevicePrivateKey(vaultId, privKey);
    });

    test('first entry (no parent) carries pubKey + a valid signature', () async {
      final entry = _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId);
      final signed = await signer.sign(entry, 'pages/notes/ideas.md', vaultId: vaultId, devicePublicKeyBase64Url: pubKey);

      expect(signed.pubKey, isNotNull);
      expect(signed.signature, isNotNull);

      // The signature verifies over the wire form + documentPath (the same
      // documentPath the signer used — derived from the relative path).
      final input = serializer.signingInput(signed, documentPathFromRelativePath('pages/notes/ideas.md'));
      expect(await crypto.verify(signed.pubKey!, input, signed.signature!), isTrue);
    });

    test('non-first entry (has parent) omits pubKey but still signs', () async {
      final entry = _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId);
      final signed = await signer.sign(entry, 'pages/notes/ideas.md', vaultId: vaultId, devicePublicKeyBase64Url: pubKey);

      expect(signed.pubKey, isNull, reason: 'pubKey must NOT appear on later entries (§2.3)');
      expect(signed.signature, isNotNull);
    });

    test('normalizes a legacy padded public key to base64url for pubKey', () async {
      // Re-encode the key in padded standard base64 to simulate a legacy
      // device.json value.
      final legacy = base64Encode(base64UrlDecode(pubKey));
      expect(legacy.contains('='), isTrue, reason: 'precondition: padded form');

      final entry = _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId);
      final signed = await signer.sign(entry, 'pages/notes/ideas.md', vaultId: vaultId, devicePublicKeyBase64Url: legacy);

      expect(signed.pubKey, isNotNull);
      // No padded standard-base64 markers remain — base64url, no padding.
      expect(signed.pubKey!.contains('+'), isFalse);
      expect(signed.pubKey!.contains('/'), isFalse);
      expect(signed.pubKey!.contains('='), isFalse);
      expect(signed.pubKey, pubKey);
    });

    test('an entry is returned unsigned when no private key is stored (legacy form)', () async {
      final emptyStore = FakeSecureKeyStore();
      final signer2 = OpLogSigner(crypto: crypto, secureKeyStore: emptyStore, serializer: serializer);

      final entry = _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId);
      final out = await signer2.sign(entry, 'pages/notes/ideas.md', vaultId: 'missing', devicePublicKeyBase64Url: pubKey);

      expect(out.signature, isNull);
      expect(out.pubKey, isNull);
    });
  });
}
