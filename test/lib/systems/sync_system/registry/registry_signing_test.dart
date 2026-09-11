// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_signing.dart';

Hlc _h(int ms, {int counter = 0, String dev = 'aaaaaaaa'}) => Hlc(physicalMs: ms, counter: counter, deviceId: dev);

/// Deterministic Ed25519 keys generated from a fixed entropy seed, so tests
/// are reproducible and don't depend on key randomness.
Future<({String ownerPriv, String ownerPub, String memberPriv, String memberPub})> _keys() async {
  final crypto = CryptoServiceImpl();
  final owner = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xA0 + i));
  final member = await crypto.deriveIdentityKeyPair(List.generate(32, (i) => 0xB0 + i));
  return (ownerPriv: owner.privateKeyBase64Url, ownerPub: owner.publicKeyBase64Url, memberPriv: member.privateKeyBase64Url, memberPub: member.publicKeyBase64Url);
}

UserRecord _unsignedUser(String id, {Hlc? updatedAt, Hlc? removedAt, String role = 'member', String addedBy = 'o'}) =>
    UserRecord(userId: id, name: 'name-$id', publicKey: 'pk-$id', role: role, addedBy: addedBy, updatedAt: updatedAt ?? _h(100), removedAt: removedAt, signature: '');

void main() {
  late CryptoServiceImpl crypto;
  late RegistrySigning signing;
  late String ownerPriv;
  late String ownerPub;
  late String memberPriv;
  late String memberPub;

  setUp(() async {
    crypto = CryptoServiceImpl();
    signing = RegistrySigning(crypto);
    final k = await _keys();
    ownerPriv = k.ownerPriv;
    ownerPub = k.ownerPub;
    memberPriv = k.memberPriv;
    memberPub = k.memberPub;
  });

  group('signUserRegistry (§3.2) —', () {
    UserRegistry userFile(String owner, {Hlc? rev}) => UserRegistry(
      version: 1,
      revision: rev ?? _h(500),
      parent: null,
      ownerUserId: owner,
      users: [
        _unsignedUser('o', role: 'owner', addedBy: 'o'),
        _unsignedUser('m', addedBy: 'o'),
      ],
      signature: '',
    );

    test('whole-file signature verifies under the owner identity key', () async {
      final signed = await signing.signUserRegistry(userFile('o'), ownerPrivateKey: ownerPriv, recordKeys: {'o': ownerPriv});
      expect(signed.signature, isNotEmpty);
      final result = await signing.verifyUserRegistry(signed, _provider(owner: ownerPub));
      expect(result.valid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('each record signature verifies under its addedBy identity key', () async {
      final signed = await signing.signUserRegistry(userFile('o'), ownerPrivateKey: ownerPriv, recordKeys: {'o': ownerPriv});
      final owner = signed.usersById['o']!;
      final member = signed.usersById['m']!;
      // Record signatures are non-trivial and mutually distinct.
      expect(owner.signature, isNot(equals('')));
      expect(member.signature, isNot(equals('')));
      // Directly verify each record against the addedBy key.
      expect(await signing.verifyRecord(owner, ownerPub), isTrue);
      expect(await signing.verifyRecord(member, ownerPub), isTrue);
      // A record does NOT verify under a different key.
      expect(await signing.verifyRecord(member, memberPub), isFalse);
    });

    test('signing is a function of the unsigned content (tamper → fails)', () async {
      final signed = await signing.signUserRegistry(userFile('o'), ownerPrivateKey: ownerPriv, recordKeys: {'o': ownerPriv});
      // Tamper with a record field: the whole-file signature and the
      // per-record signature must both fail.
      final tamperedUser = UserRecord(
        userId: 'm',
        name: 'EVIL',
        publicKey: 'pk-m',
        role: 'member',
        addedBy: 'o',
        updatedAt: signed.usersById['m']!.updatedAt,
        removedAt: null,
        signature: signed.usersById['m']!.signature,
      );
      final tampered = UserRegistry(
        version: signed.version,
        revision: signed.revision,
        parent: signed.parent,
        ownerUserId: signed.ownerUserId,
        users: [signed.usersById['o']!, tamperedUser],
        signature: signed.signature,
      );
      final result = await signing.verifyUserRegistry(tampered, _provider(owner: ownerPub));
      expect(result.valid, isFalse);
      final scopes = result.issues.map((i) => i.scope).toSet();
      expect(scopes, contains('file'));
      expect(scopes, contains('m'));
    });

    test('a whole-file signature by a non-owner key fails', () async {
      final unsigned = userFile('o');
      // Sign the file with the member key but claim owner_user_id = o.
      var signed = await signing.signUserRegistry(unsigned, ownerPrivateKey: memberPriv, recordKeys: {'o': ownerPriv});
      final result = await signing.verifyUserRegistry(signed, _provider(owner: ownerPub));
      expect(result.valid, isFalse);
      expect(result.issues.any((i) => i.scope == 'file'), isTrue);
      signed = await signing.signUserRegistry(unsigned, ownerPrivateKey: ownerPriv, recordKeys: {'o': ownerPriv});
      expect(signed.ownerUserId, 'o');
    });

    test('missing addedBy signing key is an ArgumentError', () async {
      final file = userFile('o');
      expect(() => signing.signUserRegistry(file, ownerPrivateKey: ownerPriv, recordKeys: const {}), throwsA(isA<ArgumentError>()));
    });
  });

  group('signDeviceRegistry (§3.3) —', () {
    DeviceRegistry deviceFile(String user, {Hlc? rev}) => DeviceRegistry(
      version: 1,
      revision: rev ?? _h(500),
      parent: null,
      userId: user,
      devices: [
        DeviceRecord(deviceUuid: 'd1', devicePublicKey: 'pk-d1', userId: user, deviceName: 'dev1', issuedAt: _h(90), updatedAt: _h(100), removedAt: null, signature: ''),
        DeviceRecord(deviceUuid: 'd2', devicePublicKey: 'pk-d2', userId: user, deviceName: 'dev2', issuedAt: _h(90), updatedAt: _h(100), removedAt: null, signature: ''),
      ],
      signature: '',
    );

    test('whole-file + record signatures verify under the owning user key', () async {
      final signed = await signing.signDeviceRegistry(deviceFile('u1'), userPrivateKey: ownerPriv);
      final result = await signing.verifyDeviceRegistry(signed, _provider(owner: ownerPub));
      expect(result.valid, isTrue);
      expect(result.issues, isEmpty);
      for (final device in signed.devices) {
        expect(await signing.verifyRecord(device, ownerPub), isTrue);
      }
    });

    test('a record from a different user fails under the file user key', () async {
      // d1 is signed by user A's key, but the file claims user B.
      final aFile = await signing.signDeviceRegistry(deviceFile('u1'), userPrivateKey: ownerPriv);
      final bKey = RegistrySigning(crypto);
      final bFile = await bKey.signDeviceRegistry(deviceFile('u1'), userPrivateKey: memberPriv);
      // Replace one of B's records with A's signed record: verification of
      // that record under B's key must fail.
      final mixed = DeviceRegistry(
        version: aFile.version,
        revision: aFile.revision,
        parent: aFile.parent,
        userId: 'u1',
        devices: [aFile.devices.first, bFile.devices.last],
        signature: bFile.signature,
      );
      final result = await signing.verifyDeviceRegistry(mixed, _provider(owner: memberPub));
      expect(result.valid, isFalse);
      expect(result.issues.any((i) => i.scope == 'd1'), isTrue);
    });
  });

  group('file-only signing (merge result, §3.2/§3.3) —', () {
    test('signUserFileOnly signs the file without touching record signatures', () async {
      final owner = await signing.signUserRecord(_unsignedUser('o', role: 'owner', addedBy: 'o'), ownerPriv);
      final unsigned = UserRegistry(version: 1, revision: _h(700), parent: _h(600), ownerUserId: 'o', users: [owner], signature: '');
      final signed = await signing.signUserFileOnly(unsigned, ownerPrivateKey: ownerPriv);
      expect(signed.signature, isNot(equals(unsigned.signature)));
      expect(signed.users.single.signature, owner.signature); // record signature preserved
      final result = await signing.verifyUserRegistry(signed, _provider(owner: ownerPub));
      expect(result.valid, isTrue);
    });

    test('signDeviceFileOnly signs the file without touching record signatures', () async {
      final device = await signing.signDeviceRecord(
        DeviceRecord(deviceUuid: 'd1', devicePublicKey: 'pk-d1', userId: 'u1', deviceName: 'dev1', issuedAt: _h(90), updatedAt: _h(100), removedAt: null, signature: ''),
        ownerPriv,
      );
      final unsigned = DeviceRegistry(version: 1, revision: _h(700), parent: _h(600), userId: 'u1', devices: [device], signature: '');
      final signed = await signing.signDeviceFileOnly(unsigned, userPrivateKey: ownerPriv);
      expect(signed.devices.single.signature, device.signature);
      final result = await signing.verifyDeviceRegistry(signed, _provider(owner: ownerPub));
      expect(result.valid, isTrue);
    });
  });

  group('verification failures are reported (§3.4) —', () {
    test('unknown authority key → file scope issue', () async {
      final file = await signing.signUserRegistry(
        UserRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          ownerUserId: 'unknown',
          users: [UserRecord(userId: 'unknown', name: 'x', publicKey: ownerPub, role: 'owner', addedBy: 'unknown', updatedAt: _h(1), removedAt: null, signature: '')],
          signature: '',
        ),
        ownerPrivateKey: ownerPriv,
        recordKeys: {'unknown': ownerPriv},
      );
      final result = await signing.verifyUserRegistry(file, _provider(owner: null));
      expect(result.valid, isFalse);
      expect(result.issues.single.scope, 'file');
      expect(result.issues.single.message, contains('no identity key'));
    });
  });
}

/// A minimal key provider: [owner] is the file authority key; every record's
/// addedBy resolves to the same key (in these tests the owner signs all
/// records, matching the v1 §3.6 rule).
IRegistryKeyProvider _provider({String? owner}) {
  final known = owner == null ? <String, String>{} : <String, String>{'o': owner, 'unknown': owner, 'u1': owner};
  return _StaticKeyProvider(known);
}

class _StaticKeyProvider implements IRegistryKeyProvider {
  const _StaticKeyProvider(this.keys);

  final Map<String, String> keys;

  @override
  Future<String?> identityKeyFor(String userId) async => keys[userId];
}
