// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/systems/oplog_system/oplog_models.dart';

/// The default maximum clock drift (ms) an implementation tolerates when
/// reading **other** devices' OpLog entries (sync-security.md §6).
///
/// `entry.hlc.physicalMs` MUST be `<= localTime + kDefaultMaxClockDriftMs`.
/// A configured bound MAY be larger (NOET-57) but MUST NOT be smaller — a
/// tighter bound manufactures false positives without strengthening the
/// guarantee, because the adversary chooses their own timestamps arbitrarily
/// far in the future (docs/decisions/0008-hlc-drift-validation.md).
const int kDefaultMaxClockDriftMs = 60000;

/// Pure, filesystem-free application of the sync-security.md §6 HLC drift
/// bound to a single device file's entries (in file order).
///
/// [entries] are the device file's entries as read, already signature-verified
/// and attribution-checked (sync-security.md §7 steps 1–5). Because
/// `physicalMs` is non-decreasing across a device's own file
/// (`Hlc.now` = `max(wallMs, last.physicalMs)`), the violating set is always a
/// **suffix**: the first entry with `physicalMs > localMs + maxDriftMs` and
/// every entry after it. [check] finds that first violation and cuts there.
///
/// Returns:
/// - `accepted`: the accepted prefix `entries[0, N)` — the only entries that
///   may contribute to the DAG / merge / witness state (§6: rejected entries
///   MUST NOT enter the DAG and MUST NOT advance the local HLC).
/// - `rejectedCount`: the number of entries dropped from the drifted suffix
///   (`entries.length - N`; `0` when the whole file is within the bound).
/// - `observedDriftMs`: how far ahead of the reader's clock the device's
///   newest rejected entry is — `max(physicalMs)` over the suffix minus
///   `localMs` (`0` when nothing was rejected). This is what the rejection
///   report names as "the observed drift" so the user can see how far ahead
///   the device is (§9.4).
final class HlcDriftGate {
  HlcDriftGate._();

  static ({List<OpLogEntry> accepted, int rejectedCount, int observedDriftMs}) check(List<OpLogEntry> entries, int localMs, {int maxDriftMs = kDefaultMaxClockDriftMs}) {
    final bound = localMs + maxDriftMs;

    // First entry whose physicalMs is above the bound (physicalMs is
    // non-decreasing, so this is also the start of the whole violating
    // suffix). Past timestamps are always valid (a slow device is not an
    // attack, §6), so only `> bound` rejects.
    var firstViolation = entries.length;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].hlc.physicalMs > bound) {
        firstViolation = i;
        break;
      }
    }

    final rejectedCount = entries.length - firstViolation;
    if (rejectedCount == 0) {
      // Common case: nothing drifted — hand the list back as-is rather than
      // copying it (check runs for every device file of every page in every
      // cycle).
      return (accepted: entries, rejectedCount: 0, observedDriftMs: 0);
    }

    final accepted = entries.sublist(0, firstViolation);

    // Observed drift = how far ahead the device's newest rejected entry is.
    // Every rejected entry has physicalMs > bound >= localMs, so the result
    // is strictly positive.
    var maxMs = localMs;
    for (var i = firstViolation; i < entries.length; i++) {
      final ms = entries[i].hlc.physicalMs;
      if (ms > maxMs) maxMs = ms;
    }
    return (accepted: accepted, rejectedCount: rejectedCount, observedDriftMs: maxMs - localMs);
  }
}
