// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_reconciler.dart';

Hlc _h(int ms, {int counter = 0, String dev = 'aaaaaaaa'}) => Hlc(physicalMs: ms, counter: counter, deviceId: dev);

UserRecord _user(String id, {String name = 'n', Hlc? updatedAt, Hlc? removedAt, String role = 'member'}) =>
    UserRecord(userId: id, name: name, publicKey: 'pk-$id', role: role, addedBy: 'o', updatedAt: updatedAt ?? _h(0), removedAt: removedAt, signature: 'sig');

DeviceRecord _dev(String id, {String name = 'd', Hlc? issuedAt, Hlc? updatedAt, Hlc? removedAt}) => DeviceRecord(
  deviceUuid: id,
  devicePublicKey: 'pk-$id',
  userId: 'u1',
  deviceName: name,
  issuedAt: issuedAt ?? _h(0),
  updatedAt: updatedAt ?? _h(0),
  removedAt: removedAt,
  signature: 'sig',
);

void main() {
  final reconciler = RegistryReconciler();

  group('two-branch merge from a common parent (acceptance: no loss) —', () {
    test('concurrent edits to different records both survive', () {
      final base = _user('a', updatedAt: _h(100));
      final baseUsers = [base];
      // Branch 1 adds record "b" (a new side, absent from base).
      final ours = [base, _user('b', updatedAt: _h(200))];
      // Branch 2 modifies record "a" (updatedAt newer than base).
      final theirs = [_user('a', updatedAt: _h(300), name: 'a-edited')];
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(label: RegistryReconciler.baseLabel, records: baseUsers),
          RegistryMergeSide(label: 'ours.json', records: ours),
          RegistryMergeSide(label: 'theirs.json', records: theirs),
        ],
      );
      final byId = {for (final r in result.merged) r.recordId: r};
      expect(byId, hasLength(2));
      expect(byId['a']!.toWireMap()['name'], 'a-edited'); // the edit wins
      expect(byId['a']!.updatedAt, _h(300));
      expect(byId['b']!.updatedAt, _h(200)); // the addition survives
    });

    test('a record edited on only one side is not reported as a cross-side conflict', () {
      final base = [_user('a', updatedAt: _h(100)), _user('b', updatedAt: _h(100))];
      final ours = [_user('a', updatedAt: _h(200), name: 'a-edited'), _user('b', updatedAt: _h(100))];
      final theirs = [_user('a', updatedAt: _h(100)), _user('b', updatedAt: _h(300), name: 'b-edited')];
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(label: RegistryReconciler.baseLabel, records: base),
          RegistryMergeSide(label: 'ours.json', records: ours),
          RegistryMergeSide(label: 'theirs.json', records: theirs),
        ],
      );
      // Each record is edited on only ONE side (the other carries the base
      // value), so neither is a cross-side conflict: no decisions. A naive
      // 3-way merge that flagged "ours changed / theirs didn't" would report
      // two; the base-exclusion refinement must not.
      expect(result.decisions, isEmpty);
      expect(result.merged, hasLength(2));
    });
  });

  group('same-record LWW (acceptance: deterministic by HLC) —', () {
    test('the latest updatedAt wins regardless of side order', () {
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'a.json',
            records: [_user('x', updatedAt: _h(300), name: 'from-a')],
          ),
          RegistryMergeSide(
            label: 'b.json',
            records: [_user('x', updatedAt: _h(200), name: 'from-b')],
          ),
        ],
      );
      expect(result.merged, hasLength(1));
      expect(result.merged.single.toWireMap()['name'], 'from-a');
      expect(result.decisions.single.winnerSource, 'a.json');
      expect(result.decisions.single.strategy, 'lww');
    });

    test('a tombstone beats an older live record', () {
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'live.json',
            records: [_user('x', updatedAt: _h(200))],
          ),
          RegistryMergeSide(
            label: 'tomb.json',
            records: [_user('x', updatedAt: _h(150), removedAt: _h(900))],
          ),
        ],
      );
      expect(result.merged.single.removedAt, _h(900));
    });

    test('re-add after revoke wins when newer', () {
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', removedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'readd.json',
            records: [_user('x', updatedAt: _h(950), name: 're-added')],
          ),
        ],
      );
      expect(result.merged.single.removedAt, isNull);
      expect(result.merged.single.toWireMap()['name'], 're-added');
    });

    test('identical HLC stamps break deterministically by canonical JSON + are reported', () {
      final resultA = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'a.json',
            records: [_user('x', updatedAt: _h(200), name: 'alpha')],
          ),
          RegistryMergeSide(
            label: 'b.json',
            records: [_user('x', updatedAt: _h(200), name: 'beta')],
          ),
        ],
      );
      final winnerA = resultA.merged.single.toWireMap()['name'];
      // Deterministic: the same input yields the same winner on re-run.
      final rerun = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'b.json',
            records: [_user('x', updatedAt: _h(200), name: 'beta')],
          ),
          RegistryMergeSide(
            label: 'a.json',
            records: [_user('x', updatedAt: _h(200), name: 'alpha')],
          ),
        ],
      );
      expect(rerun.merged.single.toWireMap()['name'], winnerA);
      expect(resultA.decisions.single.strategy, 'lww-tie');
      expect(resultA.decisions.single.tieBreak, isTrue);
    });

    test('a cross-side conflict at equal stamps is a tie-break, not a silent discard', () {
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(0))],
          ),
          RegistryMergeSide(
            label: 'a.json',
            records: [_user('x', updatedAt: _h(5), name: 'aa')],
          ),
          RegistryMergeSide(
            label: 'b.json',
            records: [_user('x', updatedAt: _h(5), name: 'bb')],
          ),
        ],
      );
      expect(result.decisions.single.tieBreak, isTrue);
    });
  });

  group('device registry (acceptance: same-user two-device race) —', () {
    test('two devices of one user merge per-record by LWW', () {
      final base = [_dev('d1', updatedAt: _h(100))];
      final deviceA = [_dev('d1', updatedAt: _h(100)), _dev('d2', updatedAt: _h(300))];
      final deviceB = [_dev('d1', updatedAt: _h(200), name: 'renamed')];
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(label: RegistryReconciler.baseLabel, records: base),
          RegistryMergeSide(label: 'devA.json', records: deviceA),
          RegistryMergeSide(label: 'devB.json', records: deviceB),
        ],
      );
      final byId = {for (final r in result.merged) r.recordId: r};
      expect(byId, hasLength(2));
      expect(byId['d1']!.deviceName, 'renamed'); // d1: newer edit wins
      expect(byId['d2']!.updatedAt, _h(300)); // d2: only on device A
    });
  });

  group('algebraic properties (acceptance: idempotent + commutative) —', () {
    test('the merge is commutative in the candidate order', () {
      final base = [_user('x', updatedAt: _h(100)), _user('y', updatedAt: _h(100))];
      final ours = [_user('x', updatedAt: _h(200), name: 'x2'), _user('y', updatedAt: _h(100))];
      final theirs = [_user('x', updatedAt: _h(100)), _user('y', updatedAt: _h(300), name: 'y3')];
      List<UserRecord> mergeWith(List<RegistryMergeSide<UserRecord>> sides) => reconciler.merge(sides: sides).merged;
      final f = mergeWith([
        RegistryMergeSide(label: RegistryReconciler.baseLabel, records: base),
        RegistryMergeSide(label: 'ours', records: ours),
        RegistryMergeSide(label: 'theirs', records: theirs),
      ]);
      final swapped = mergeWith([
        RegistryMergeSide(label: RegistryReconciler.baseLabel, records: base),
        RegistryMergeSide(label: 'theirs', records: theirs),
        RegistryMergeSide(label: 'ours', records: ours),
      ]);
      expect(swapped.map((r) => r.toWireMap()).toList(), f.map((r) => r.toWireMap()).toList());
    });

    test('the merge is idempotent (merging a result with its inputs reproduces it)', () {
      final base = [_user('x', updatedAt: _h(100)), _user('y', updatedAt: _h(100))];
      final ours = [_user('x', updatedAt: _h(200), name: 'x2')];
      final theirs = [_user('y', updatedAt: _h(300), name: 'y3')];
      final sides = [
        RegistryMergeSide(label: RegistryReconciler.baseLabel, records: base),
        RegistryMergeSide(label: 'ours', records: ours),
        RegistryMergeSide(label: 'theirs', records: theirs),
      ];
      final first = reconciler.merge(sides: sides).merged;
      // Merge the result with one of the inputs; the winner is stable.
      final again = reconciler
          .merge(
            sides: [
              RegistryMergeSide(label: RegistryReconciler.baseLabel, records: first),
              RegistryMergeSide(label: 'ours', records: ours),
              RegistryMergeSide(label: 'theirs', records: theirs),
            ],
          )
          .merged;
      expect(again.map((r) => r.toWireMap()).toList(), first.map((r) => r.toWireMap()).toList());
    });

    test('a single source and unanimous candidates are taken without a decision', () {
      final result = reconciler.merge(
        sides: [
          RegistryMergeSide(
            label: RegistryReconciler.baseLabel,
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'a.json',
            records: [_user('x', updatedAt: _h(100))],
          ),
          RegistryMergeSide(
            label: 'b.json',
            records: [_user('x', updatedAt: _h(100))],
          ),
        ],
      );
      expect(result.merged, hasLength(1));
      expect(result.decisions, isEmpty);
    });

    test('two sides adding the identical record is not a conflict', () {
      final rec = _user('n', updatedAt: _h(200));
      final result = reconciler.merge(
        sides: [
          const RegistryMergeSide(label: RegistryReconciler.baseLabel, records: <UserRecord>[]),
          RegistryMergeSide(label: 'a.json', records: [rec]),
          RegistryMergeSide(label: 'b.json', records: [rec]),
        ],
      );
      expect(result.merged, hasLength(1));
      expect(result.decisions, isEmpty);
    });
  });

  group('file-level LWW fallback (acceptance: no common ancestor) —', () {
    test('is exercised by the service, not the reconciler (no-op here)', () {
      // The fallback lives in RegistryServiceImpl (see registry_service_test);
      // the reconciler only performs per-record LWW. This guards the API.
      expect(RegistryReconciler.baseLabel, 'base');
    });
  });
}
