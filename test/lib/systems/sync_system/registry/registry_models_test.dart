// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';

Hlc _h(int ms, {int counter = 0, String dev = 'aaaaaaaa'}) => Hlc(physicalMs: ms, counter: counter, deviceId: dev);

UserRecord _user(String id, {String name = 'n', Hlc? updatedAt, Hlc? removedAt, String role = 'member', String addedBy = 'owner'}) =>
    UserRecord(userId: id, name: name, publicKey: 'pk-$id', role: role, addedBy: addedBy, updatedAt: updatedAt ?? _h(0), removedAt: removedAt, signature: 'sig');

DeviceRecord _dev(String id, {String name = 'd', Hlc? issuedAt, Hlc? updatedAt, Hlc? removedAt, String userId = 'u1'}) => DeviceRecord(
  deviceUuid: id,
  devicePublicKey: 'pk-$id',
  userId: userId,
  deviceName: name,
  issuedAt: issuedAt ?? _h(0),
  updatedAt: updatedAt ?? _h(0),
  removedAt: removedAt,
  signature: 'sig',
);

void main() {
  group('UserRegistry wire format —', () {
    test('round-trips every spec field (§3.2)', () {
      final file = UserRegistry(
        version: 1,
        revision: _h(2000),
        parent: _h(1000),
        ownerUserId: 'owner-1',
        users: [
          _user('owner-1', role: 'owner', updatedAt: _h(1500), addedBy: 'owner-1'),
          _user('member-1', removedAt: _h(1600)),
        ],
        signature: 'file-sig',
      );
      final wire = file.toWireMap();
      expect(wire['version'], 1);
      expect(wire['revision'], '2000-0000-aaaaaaaa');
      expect(wire['parent'], '1000-0000-aaaaaaaa');
      expect(wire['owner_user_id'], 'owner-1');
      expect(wire['signature'], 'file-sig');
      final users = wire['users'] as List<Map<String, dynamic>>;
      expect(users, hasLength(2));
      expect(users[0]['userId'], 'owner-1');
      expect(users[0]['role'], 'owner');
      expect(users[1]['removedAt'], '1600-0000-aaaaaaaa'); // tombstone keeps its stamp
      expect(users[0]['removedAt'], isNull); // nulls are never omitted

      final parsed = UserRegistry.fromWireMap(wire);
      expect(parsed, isA<UserRegistry>());
      expect(parsed.ownerUserId, 'owner-1');
      expect(parsed.users, hasLength(2));
      expect(parsed.usersById['member-1']!.removedAt, _h(1600));
      expect(parsed.revision, _h(2000));
      expect(parsed.parent, _h(1000));
    });

    test('toUnsignedWireMap removes only the top-level signature', () {
      final file = UserRegistry(
        version: 1,
        revision: _h(2000),
        parent: null,
        ownerUserId: 'o',
        users: [_user('o', role: 'owner')],
        signature: 'sig',
      );
      final unsigned = file.toUnsignedWireMap();
      expect(unsigned.containsKey('signature'), isFalse);
      expect(unsigned['users'], isA<List>());
      expect((unsigned['users'] as List<Map<String, dynamic>>).first.containsKey('signature'), isTrue); // per-record signatures stay
      expect(file.toWireMap().containsKey('signature'), isTrue);
    });

    test('withFileSignature copies the file, replacing the signature', () {
      final file = UserRegistry(
        version: 1,
        revision: _h(2000),
        parent: null,
        ownerUserId: 'o',
        users: [_user('o', role: 'owner')],
        signature: 'old',
      );
      final updated = file.withFileSignature('new');
      expect(updated.signature, 'new');
      expect(file.signature, 'old');
      expect(updated.revision, file.revision);
    });

    test('validate() enforces version, roles, unique ids, owner record (§3.2)', () {
      UserRegistry valid() => UserRegistry(
        version: 1,
        revision: _h(1),
        parent: null,
        ownerUserId: 'o',
        users: [
          _user('o', role: 'owner'),
          _user('m'),
        ],
        signature: 's',
      );
      valid().validate(); // no throw
      expect(
        () => UserRegistry(
          version: 2,
          revision: _h(1),
          parent: null,
          ownerUserId: 'o',
          users: [_user('o', role: 'owner')],
          signature: 's',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => UserRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          ownerUserId: 'o',
          users: [_user('o', role: 'boss')],
          signature: 's',
        ).validate(),
        throwsA((e) => e is FormatException && e.message.contains('invalid role')),
      );
      expect(
        () => UserRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          ownerUserId: 'o',
          users: [
            _user('o', role: 'owner'),
            _user('o', role: 'member'),
          ],
          signature: 's',
        ).validate(),
        throwsA((e) => e is FormatException && e.message.contains('duplicate')),
      );
      expect(
        () => UserRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          ownerUserId: 'missing',
          users: [_user('o', role: 'owner')],
          signature: 's',
        ).validate(),
        throwsA((e) => e is FormatException && e.message.contains('no record')),
      );
      expect(
        () => UserRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          ownerUserId: 'o',
          users: [_user('o', role: 'member')],
          signature: 's',
        ).validate(),
        throwsA((e) => e is FormatException && e.message.contains('owner') && e.message.contains('role')),
      );
    });

    test('fromWireMap rejects malformed wire data', () {
      final base = UserRegistry(version: 1, revision: _h(1), parent: null, ownerUserId: 'o', users: const [], signature: 's').toWireMap();
      expect(() => UserRegistry.fromWireMap({...base, 'version': 'one'}), throwsFormatException);
      expect(() => UserRegistry.fromWireMap({...base, 'users': 'nope'}), throwsFormatException);
      expect(() => UserRegistry.fromWireMap({...base, 'revision': 123}), throwsFormatException);
    });
  });

  group('DeviceRegistry wire format —', () {
    test('round-trips every spec field (§3.3)', () {
      final file = DeviceRegistry(
        version: 1,
        revision: _h(2000),
        parent: _h(1000),
        userId: 'u1',
        devices: [
          _dev('d1'),
          _dev('d2', removedAt: _h(1700)),
        ],
        signature: 'fs',
      );
      final wire = file.toWireMap();
      expect(wire['userId'], 'u1');
      expect(wire['devices'], hasLength(2));
      final devices = wire['devices'] as List<Map<String, dynamic>>;
      expect(devices[0]['deviceUuid'], 'd1');
      expect(devices[1]['removedAt'], '1700-0000-aaaaaaaa');
      final parsed = DeviceRegistry.fromWireMap(wire);
      expect(parsed.devicesById['d2']!.removedAt, _h(1700));
      expect(parsed.userId, 'u1');
    });

    test('validate() enforces version, per-record userId, unique deviceUuid (§3.3)', () {
      DeviceRegistry valid() => DeviceRegistry(version: 1, revision: _h(1), parent: null, userId: 'u1', devices: [_dev('d1'), _dev('d2')], signature: 's');
      valid().validate();
      expect(() => DeviceRegistry(version: 3, revision: _h(1), parent: null, userId: 'u1', devices: const [], signature: 's').validate(), throwsFormatException);
      expect(
        () => DeviceRegistry(
          version: 1,
          revision: _h(1),
          parent: null,
          userId: 'u1',
          devices: [_dev('d1', userId: 'u2')],
          signature: 's',
        ).validate(),
        throwsA((e) => e is FormatException && e.message.contains('userId')),
      );
      expect(
        () => DeviceRegistry(version: 1, revision: _h(1), parent: null, userId: 'u1', devices: [_dev('d1'), _dev('d1')], signature: 's').validate(),
        throwsA((e) => e is FormatException && e.message.contains('duplicate')),
      );
    });

    test('fileKey is devices/<userId>.json', () {
      expect(DeviceRegistry(version: 1, revision: _h(1), parent: null, userId: 'u1', devices: const [], signature: 's').fileKey, 'devices/u1.json');
      expect(UserRegistry(version: 1, revision: _h(1), parent: null, ownerUserId: 'o', users: const [], signature: 's').fileKey, 'users.json');
    });
  });

  group('RegistryRecord contract —', () {
    test('changeHlc: tombstone by removedAt, live by updatedAt (§3.7)', () {
      final live = _user('x', updatedAt: _h(500));
      final tomb = _user('x', updatedAt: _h(400), removedAt: _h(900));
      expect(live.changeHlc, _h(500));
      expect(tomb.changeHlc, _h(900));
      expect(live.recordId, 'x');
      expect(_dev('d').changeHlc, _h(0));
    });

    test('toUnsignedWireMap drops the record signature only', () {
      final r = _user('x');
      expect(r.toUnsignedWireMap().containsKey('signature'), isFalse);
      expect(r.toWireMap().containsKey('signature'), isTrue);
      expect(r.toUnsignedWireMap()['userId'], 'x');
    });
  });
}
