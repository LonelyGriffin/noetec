// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';
import 'package:noetec/systems/oplog_system/oplog_verifier.dart';

import '../../../helpers/test_fakes.dart';

OpLogEntry _entry({required Hlc hlc, Hlc? parent, required OpEntryType type, required String deviceId}) =>
    OpLogEntry(version: 1, hlc: hlc, parent: parent, parentB: null, type: type, blockOps: null, fileOp: null, fileHash: null, deviceId: deviceId);

void main() {
  const serializer = OpLogSerializer();
  final crypto = CryptoServiceImpl();

  group('OpLogVerifier.verifyFile (§2.4) —', () {
    late FakeSecureKeyStore store;
    late String pubKey;
    late String privKey;
    const deviceId = 'dev1-uuid-here-xxxx-xxxxxxxxxxxx';
    const vaultId = 'vault-1';
    const relativePath = 'pages/notes/ideas.md';

    // Signs [entry] for [path], publishing [pubKey] on the first entry and
    // signing with the private key stored for [vaultId].
    Future<OpLogEntry> sign(OpLogEntry entry, String path, {required String pubKey, required String vaultId}) async {
      final signer = OpLogSigner(crypto: crypto, secureKeyStore: store, serializer: serializer);
      return signer.sign(entry, path, vaultId: vaultId, devicePublicKeyBase64Url: pubKey);
    }

    // Signs [entry] for [path] with a *different* (attacker) key pair, whose
    // private key is stored for [attackerVault]. The signature will NOT
    // verify under the file's published pubKey.
    Future<OpLogEntry> signAsAttacker(OpLogEntry entry, String path, {required String attackerPubKey, required String attackerPrivKey, required String attackerVault}) async {
      final attackerStore = FakeSecureKeyStore();
      await attackerStore.storeDevicePrivateKey(attackerVault, attackerPrivKey);
      final signer = OpLogSigner(crypto: crypto, secureKeyStore: attackerStore, serializer: serializer);
      return signer.sign(entry, path, vaultId: attackerVault, devicePublicKeyBase64Url: attackerPubKey);
    }

    late String attackerPubKey;
    late String attackerPrivKey;
    const attackerVault = 'attacker-vault';

    setUp(() async {
      store = FakeSecureKeyStore();
      final pair = await crypto.generateDeviceKeyPair();
      pubKey = pair.publicKeyBase64Url;
      privKey = pair.privateKeyBase64Url;
      await store.storeDevicePrivateKey(vaultId, privKey);

      final attacker = await crypto.generateDeviceKeyPair();
      attackerPubKey = attacker.publicKeyBase64Url;
      attackerPrivKey = attacker.privateKeyBase64Url;
    });

    test('all valid entries are accepted (first carries pubKey)', () async {
      final e1 = await sign(
        _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      final e2 = await sign(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      final e3 = await sign(
        _entry(hlc: Hlc.fromKey('300-0000-dev1'), parent: Hlc.fromKey('200-0000-dev1'), type: OpEntryType.save, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );

      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile(relativePath, [e1, e2, e3]);

      expect(accepted, hasLength(3));
      expect(accepted.first.hlcKey, '100-0000-dev1');
      expect(accepted.last.hlcKey, '300-0000-dev1');
    });

    test('a forged entry (wrong key) is rejected and the rest of the chain drops', () async {
      final e1 = await sign(
        _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      // The attacker forges the second entry under the victim's deviceId,
      // signing it with their own key. The file's published pubKey is the
      // device key, so the forged entry must not verify.
      final forged = await signAsAttacker(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId),
        relativePath,
        attackerPubKey: attackerPubKey,
        attackerPrivKey: attackerPrivKey,
        attackerVault: attackerVault,
      );
      final e3 = await sign(
        _entry(hlc: Hlc.fromKey('300-0000-dev1'), parent: Hlc.fromKey('200-0000-dev1'), type: OpEntryType.save, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );

      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile(relativePath, [e1, forged, e3]);

      expect(accepted, hasLength(1), reason: 'only the first valid entry remains');
      expect(accepted.first.hlcKey, '100-0000-dev1');
    });

    test('an entry replayed into another document (path binding) is rejected', () async {
      // The entries are legitimately signed for `notes/ideas` …
      final e1 = await sign(
        _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId),
        'pages/notes/ideas.md',
        pubKey: pubKey,
        vaultId: vaultId,
      );
      final e2 = await sign(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId),
        'pages/notes/ideas.md',
        pubKey: pubKey,
        vaultId: vaultId,
      );

      // … but are then verified under a different document path: the signature
      // (which binds documentPath) no longer matches.
      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile('pages/other/doc.md', [e1, e2]);

      expect(accepted, isEmpty, reason: 'replayed entries must not verify in another document (§2.2, threat 4)');
    });

    test('a tampered entry (field changed after signing) is rejected with chain rejection', () async {
      final e1 = await sign(
        _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      final e2Signed = await sign(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.save, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      // Adversary rewrites the save entry's fileHash after signing; the stale
      // signature no longer matches the changed wire bytes.
      final mutated = OpLogEntry(
        version: 1,
        hlc: e2Signed.hlc,
        parent: e2Signed.parent,
        parentB: null,
        type: OpEntryType.save,
        blockOps: null,
        fileOp: null,
        fileHash: 'sha256:attacker',
        deviceId: e2Signed.deviceId,
        signature: e2Signed.signature,
        pubKey: e2Signed.pubKey,
      );

      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile(relativePath, [e1, mutated]);

      expect(accepted, hasLength(1));
      expect(accepted.first.hlcKey, '100-0000-dev1');
    });

    test('a mixed legacy + signed file verifies correctly (§8.1)', () async {
      // Legacy (unsigned) first entry — no pubKey, no signature.
      final legacy = _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId);
      // A signed second entry. It has a parent, so it is NOT the file's first
      // entry and carries no pubKey; the file has no pubKey at all, so the
      // verifier must resolve the local device's key (device.json).
      final signed = await sign(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      expect(signed.pubKey, isNull, reason: 'a non-first entry must not carry pubKey');

      final accepted = await OpLogVerifier(
        crypto: crypto,
        serializer: serializer,
        keyResolver: (d) async => d == deviceId ? pubKey : null,
      ).verifyFile(relativePath, [legacy, signed]);

      expect(accepted, hasLength(2), reason: 'legacy entry is accepted and does not start chain rejection; the signed entry verifies via the resolver');
    });

    test('legacy entries do not start a chain rejection even when a later entry is forged', () async {
      final legacy = _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: deviceId);
      final forged = await signAsAttacker(
        _entry(hlc: Hlc.fromKey('200-0000-dev1'), parent: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.edit, deviceId: deviceId),
        relativePath,
        attackerPubKey: attackerPubKey,
        attackerPrivKey: attackerPrivKey,
        attackerVault: attackerVault,
      );

      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile(relativePath, [legacy, forged]);

      expect(accepted, hasLength(1));
      expect(accepted.first.hlcKey, '100-0000-dev1');
    });

    test('a signed entry in a file with no resolvable key is rejected (structurally unverifiable)', () async {
      final signed = await sign(
        _entry(hlc: Hlc.fromKey('100-0000-dev1'), type: OpEntryType.fileCreate, deviceId: 'unknown-remote-device'),
        relativePath,
        pubKey: pubKey,
        vaultId: vaultId,
      );
      // Strip the pubKey so the file has none, and provide no resolver.
      final stripped = signed.withSignature(signature: signed.signature, pubKey: null);

      final accepted = await OpLogVerifier(crypto: crypto, serializer: serializer).verifyFile(relativePath, [stripped]);

      expect(accepted, isEmpty, reason: 'no key available to verify → entry + chain rejected');
    });
  });
}
