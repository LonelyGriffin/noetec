// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:canonical_json/canonical_json.dart' as cj;
import 'package:logging/logging.dart';

import 'registry_record.dart';

/// One side of a registry merge: a labelled set of records (one parsed
/// registry file, or the base).
final class RegistryMergeSide<T extends RegistryRecord> {
  const RegistryMergeSide({required this.label, required this.records});

  /// The side's label (e.g. `'base'`, a file name, or `'known-good'` for the
  /// last known-good cache).
  final String label;

  /// The side's records. A side may omit a record (absent on that side).
  final List<T> records;
}

/// A per-record merge decision (part of the reconciler report).
final class RecordMergeDecision {
  const RecordMergeDecision({required this.key, required this.strategy, this.tieBreak = false, required this.winnerSource, this.loserSources = const []});

  /// The record's merge key (a `userId` or `deviceUuid`).
  final String key;

  /// How the record was resolved: `lww` (the later HLC won) or `lww-tie`
  /// (identical HLC stamps, broken by canonical JSON, §3.7).
  final String strategy;

  /// `true` when an identical-HLC tie was broken deterministically by
  /// `canonicalJson` (§3.7) — always reported.
  final bool tieBreak;

  /// Which side the winning record came from (a side label).
  final String winnerSource;

  /// The sides that lost (side labels).
  final List<String> loserSources;

  @override
  String toString() {
    final tie = tieBreak ? ', tie-break' : '';
    final losers = loserSources.isEmpty ? '' : ', lost ${loserSources.join(' | ')}';
    return 'record $key: $strategy ($winnerSource)[$tie$losers]';
  }
}

/// The outcome of merging one registry file: the merged record list plus the
/// per-record decisions that explain every cross-side conflict.
final class RegistryMergeResult<T extends RegistryRecord> {
  const RegistryMergeResult({required this.merged, required this.decisions});

  /// The merged records (one per unique key, deterministic sorted order).
  /// Tombstoned records are kept — `removedAt` is part of the state (§3.6).
  final List<T> merged;

  /// The decisions for records where two or more sides changed the record
  /// to differing values (resolved by LWW, with a canonical-JSON tie-break
  /// on identical HLC stamps).
  final List<RecordMergeDecision> decisions;
}

/// N-way, last-write-wins **per record** registry merge
/// (sync-security.md §3.7, ADR-0007 §5).
///
/// Given the base (common ancestor, or the last known-good revision) and the
/// candidate sides, each record (keyed by `userId`/`deviceUuid`) resolves to
/// the candidate with the latest [RegistryRecord.changeHlc]:
///
/// - present in only one side → taken (the only non-base candidate);
/// - identical on every side → taken;
/// - differing → the latest HLC wins (a tombstone is ordered by `removedAt`,
///   so it beats an older live record, and a newer live record beats a
///   tombstone);
/// - identical HLC stamps → broken **deterministically** by the canonical JSON
///   of the unsigned wire form (§3.7) — a content-based (not side-based)
///   comparison — and reported.
///
/// Because the winner is a pure function of the multiset of candidate
/// records, the merge is **commutative** (re-labelling or re-ordering sides
/// cannot change the winning record) and **idempotent** (re-merging a result
/// with any of its inputs reproduces the result).
final class RegistryReconciler {
  RegistryReconciler([Logger? log]) : _log = log ?? Logger('RegistryReconciler');

  final Logger _log;

  /// The label that marks the base side. A base side never creates a
  /// cross-side conflict by itself; it only supplies the "changed" reference.
  static const String baseLabel = 'base';

  /// Merges all [sides] (one of which should be labelled
  /// [RegistryReconciler.baseLabel]) into a single record list.
  RegistryMergeResult<T> merge<T extends RegistryRecord>({required List<RegistryMergeSide<T>> sides}) {
    final keys = <String>{};
    for (final side in sides) {
      for (final record in side.records) {
        keys.add(record.recordId);
      }
    }
    // Deterministic iteration: sort the keys. The per-record winner is
    // independent of on-disk record order and of side order.
    final sortedKeys = keys.toList()..sort();

    final merged = <T>[];
    final decisions = <RecordMergeDecision>[];
    for (final key in sortedKeys) {
      // (record, side label) for every side that carries this key.
      final candidates = <(T, String)>[
        for (final side in sides)
          if (side.records.any((r) => r.recordId == key)) (side.records.firstWhere((r) => r.recordId == key), side.label),
      ];
      if (candidates.isEmpty) {
        throw StateError('record $key resolved with no source');
      }

      final winner = _argmax(candidates);
      merged.add(winner.$1);

      final decision = _decisionFor(key, candidates, winner.$2);
      if (decision != null) {
        decisions.add(decision);
      }
    }
    return RegistryMergeResult(merged: merged, decisions: decisions);
  }

  /// Picks the winning candidate: the latest [RegistryRecord.changeHlc]; on
  /// an identical stamp, the lexicographically smaller canonical JSON of the
  /// unsigned wire form (deterministic, content-based, §3.7).
  (T, String) _argmax<T extends RegistryRecord>(List<(T, String)> candidates) {
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (_beats(candidate, best)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Whether [a] wins over [b]: a later HLC, or — on an identical HLC — a
  /// lexicographically smaller canonical-JSON unsigned wire form.
  bool _beats<T extends RegistryRecord>((T, String) a, (T, String) b) {
    final hlcCmp = a.$1.changeHlc.compareTo(b.$1.changeHlc);
    if (hlcCmp != 0) {
      return hlcCmp > 0;
    }
    return _compareBytes(_unsignedBytes(a.$1), _unsignedBytes(b.$1)) < 0;
  }

  /// Builds a report [RecordMergeDecision] when two or more sides changed the
  /// record (relative to the base) to differing values, or `null` for the
  /// trivial "take it" cases (a single source, or all sources agree).
  ///
  /// A side carrying the base's own record is *not* "changed" — it did not
  /// edit the record — so a single-sided edit is never reported as a
  /// conflict.
  RecordMergeDecision? _decisionFor<T extends RegistryRecord>(String key, List<(T, String)> candidates, String winnerLabel) {
    final baseRecord = candidates.where((c) => c.$2 == baseLabel).map((c) => c.$1).toList();
    final nonBase = candidates.where((c) => c.$2 != baseLabel).toList();

    // A non-base side is "changed" when its record differs from the base's
    // (or when the record is absent from the base — an addition).
    final baseForm = baseRecord.isEmpty ? null : _wireBytes(baseRecord.single);
    final changed = <(T, String)>[];
    for (final (record, label) in nonBase) {
      final form = _wireBytes(record);
      if (baseForm == null || _compareBytes(form, baseForm) != 0) {
        changed.add((record, label));
      }
    }
    if (changed.length < 2) {
      return null;
    }

    // The changed sides must disagree for this to be a cross-side conflict
    // (two sides adding the identical record is not a conflict).
    final firstForm = _wireBytes(changed.first.$1);
    final disagreeingLabels = <String>[];
    var allSame = true;
    for (final (record, label) in changed) {
      if (_compareBytes(_wireBytes(record), firstForm) != 0) {
        allSame = false;
      }
      disagreeingLabels.add(label);
    }
    if (allSame) {
      return null;
    }

    // Identical max HLC among the candidates means the winner was decided by
    // the canonical-JSON tie-break rather than by HLC.
    final maxHlc = candidates.map((c) => c.$1.changeHlc).reduce((a, b) => a > b ? a : b);
    final tieLevel = candidates.where((c) => c.$1.changeHlc == maxHlc).toList();
    final tieBreak = tieLevel.length > 1 && tieLevel.map((c) => _unsignedBytes(c.$1).join(',')).toSet().length > 1;

    if (tieBreak) {
      _log.info('Registry record $key: identical HLC ${maxHlc.toKey()} across sides $disagreeingLabels — tie broken by canonical JSON, winner: $winnerLabel');
    }
    return RecordMergeDecision(
      key: key,
      strategy: tieBreak ? 'lww-tie' : 'lww',
      tieBreak: tieBreak,
      winnerSource: winnerLabel,
      loserSources: [
        for (final label in disagreeingLabels)
          if (label != winnerLabel) label,
      ],
    );
  }

  List<int> _wireBytes<T extends RegistryRecord>(T record) => cj.canonicalJson.encode(record.toWireMap());

  List<int> _unsignedBytes<T extends RegistryRecord>(T record) => cj.canonicalJson.encode(record.toUnsignedWireMap());

  /// Lexicographic (total) order over canonical-JSON byte sequences.
  int _compareBytes(List<int> a, List<int> b) {
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final diff = a[i] - b[i];
      if (diff != 0) return diff;
    }
    return a.length - b.length;
  }
}
