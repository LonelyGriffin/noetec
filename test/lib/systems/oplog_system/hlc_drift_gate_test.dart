// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/systems/oplog_system/hlc_drift_gate.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

/// A minimal device file's entries in [physicalMs] order. The drift gate only
/// reads `hlc.physicalMs` (and `pubKey` upstream), so the rest of the entry is
/// irrelevant here — a single `fileCreate` entry per timestamp is enough.
List<OpLogEntry> _file(String device, List<int> physicalMs) {
  Hlc? prev;
  return [
    for (final ms in physicalMs)
      (() {
        final hlc = Hlc(physicalMs: ms, counter: 0, deviceId: device);
        final entry = OpLogEntry(
          version: 1,
          hlc: hlc,
          parent: prev,
          parentB: null,
          type: prev == null ? OpEntryType.fileCreate : OpEntryType.edit,
          blockOps: null,
          fileOp: null,
          fileHash: null,
          deviceId: device,
          signature: null,
          pubKey: prev == null ? 'pk-$device' : null,
        );
        prev = hlc;
        return entry;
      })(),
  ];
}

void main() {
  // A fixed reference clock so every expectation is exact.
  const localMs = 1000000;
  const bound = localMs + kDefaultMaxClockDriftMs; // 1060000

  group('HlcDriftGate.check (§6 drift bound, pure) —', () {
    test('the default bound is 60 000 ms', () {
      expect(kDefaultMaxClockDriftMs, 60000);
    });

    test('a fully within-bound file is fully accepted (no drift)', () {
      final r = HlcDriftGate.check(_file('d', [localMs - 1000, localMs, localMs + 59999]), localMs);
      expect(r.accepted, hasLength(3));
      expect(r.rejectedCount, 0);
      expect(r.observedDriftMs, 0);
    });

    test('an entry exactly at the bound is accepted (physicalMs <= localTime + maxDrift)', () {
      final r = HlcDriftGate.check(_file('d', [localMs, bound]), localMs);
      expect(r.accepted, hasLength(2), reason: 'physicalMs == localTime + maxDrift is within the bound');
      expect(r.rejectedCount, 0);
    });

    test('the first entry above the bound and everything after it is rejected (suffix)', () {
      // entry0 below bound, entry1 just above, entry2 far above.
      final file = _file('d', [localMs - 1000, localMs + 60001, localMs + 120000]);
      final r = HlcDriftGate.check(file, localMs);
      expect(r.accepted, hasLength(1));
      expect(identical(r.accepted.single, file.first), isTrue, reason: 'the accepted prefix is entries [0, N)');
      expect(r.rejectedCount, 2);
      expect(r.observedDriftMs, (localMs + 120000) - localMs, reason: 'observed drift is the max physicalMs in the suffix minus localMs');
    });

    test('observed drift is the maximum over the rejected suffix, not the first violation', () {
      // First violation is localMs+60001, but the suffix max is localMs+250000.
      final r = HlcDriftGate.check(_file('d', [localMs + 60001, localMs + 250000]), localMs);
      expect(r.rejectedCount, 2);
      expect(r.observedDriftMs, 250000);
    });

    test('a wholly-drifted file (N=0) is fully rejected with an empty accepted prefix', () {
      final r = HlcDriftGate.check(_file('d', [localMs + 60001, localMs + 70000]), localMs);
      expect(r.accepted, isEmpty);
      expect(r.rejectedCount, 2);
      expect(r.observedDriftMs, 70000);
    });

    test('past timestamps are always valid (a slow device is not an attack)', () {
      final r = HlcDriftGate.check(_file('d', [1, 1000, localMs - 1000000]), localMs);
      expect(r.accepted, hasLength(3));
      expect(r.rejectedCount, 0);
    });

    test('a single entry one ms above the bound is rejected with drift 60001', () {
      final r = HlcDriftGate.check(_file('d', [localMs + 60001]), localMs);
      expect(r.accepted, isEmpty);
      expect(r.rejectedCount, 1);
      expect(r.observedDriftMs, 60001);
    });

    test('a larger bound admits more (the configurable direction is looser only)', () {
      final file = _file('d', [localMs + 60001, localMs + 130000]);
      // Default bound rejects both; a larger bound admits the first.
      final defaultCheck = HlcDriftGate.check(file, localMs);
      expect(defaultCheck.rejectedCount, 2);
      final looser = HlcDriftGate.check(file, localMs, maxDriftMs: 120000);
      expect(looser.accepted, hasLength(1));
      expect(looser.rejectedCount, 1);
      expect(looser.observedDriftMs, 130000);
    });

    test('an empty file yields no rejection', () {
      final r = HlcDriftGate.check(const <OpLogEntry>[], localMs);
      expect(r.accepted, isEmpty);
      expect(r.rejectedCount, 0);
      expect(r.observedDriftMs, 0);
    });

    test('robustness: a later smaller entry after a violation is still part of the rejected suffix', () {
      // Non-monotonic (should not happen in practice, but the suffix rule is
      // "first violation and everything after it").
      final r = HlcDriftGate.check(_file('d', [localMs - 100, localMs + 60001, localMs + 50000]), localMs);
      expect(r.accepted, hasLength(1));
      expect(r.rejectedCount, 2);
      expect(r.observedDriftMs, 60001, reason: 'max over the suffix = localMs+60001');
    });
  });
}
