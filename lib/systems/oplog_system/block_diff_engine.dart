// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

class BlockDiffEngine {
  const BlockDiffEngine._();

  static List<BlockOp> compute(
    List<TextBlockEntity> previous,
    List<TextBlockEntity> current,
  ) {
    final prevMap = {for (final b in previous) b.id: b};
    final currMap = {for (final b in current) b.id: b};

    final prevIds = prevMap.keys.toSet();
    final currIds = currMap.keys.toSet();

    final deletedIds = prevIds.difference(currIds);
    final insertedIds = currIds.difference(prevIds);
    final commonIds = prevIds.intersection(currIds);

    final ops = <BlockOp>[];

    for (final id in deletedIds) {
      ops.add(BlockDelete(blockId: id));
    }

    String? afterIdInCurrent(int currentIndex) {
      if (currentIndex <= 0) return null;
      return current[currentIndex - 1].id;
    }

    for (var i = 0; i < current.length; i++) {
      final block = current[i];
      if (insertedIds.contains(block.id)) {
        ops.add(
          BlockInsert(
            blockId: block.id,
            afterBlockId: afterIdInCurrent(i),
            segments: List.of(block.segments),
          ),
        );
      }
    }

    final updatedIds = <String>{};
    for (final id in commonIds) {
      if (!blocksEqual(prevMap[id]!, currMap[id]!)) {
        updatedIds.add(id);
      }
    }
    for (var i = 0; i < current.length; i++) {
      final block = current[i];
      if (updatedIds.contains(block.id)) {
        ops.add(
          BlockUpdate(blockId: block.id, segments: List.of(block.segments)),
        );
      }
    }

    final movedIds = _detectMoves(previous, current, commonIds);
    for (var i = 0; i < current.length; i++) {
      final block = current[i];
      if (movedIds.contains(block.id)) {
        ops.add(
          BlockMove(blockId: block.id, afterBlockId: afterIdInCurrent(i)),
        );
      }
    }

    return ops;
  }

  static Set<String> _detectMoves(
    List<TextBlockEntity> previous,
    List<TextBlockEntity> current,
    Set<String> commonIds,
  ) {
    final prevOrder = [
      for (final b in previous)
        if (commonIds.contains(b.id)) b.id,
    ];
    final currOrder = [
      for (final b in current)
        if (commonIds.contains(b.id)) b.id,
    ];

    if (_listEquals(prevOrder, currOrder)) return const {};

    final prevIndexOf = {
      for (var i = 0; i < prevOrder.length; i++) prevOrder[i]: i,
    };

    final indices = [for (final id in currOrder) prevIndexOf[id]!];

    final keptPositions = _longestIncreasingSubsequence(indices);
    final keptSet = keptPositions.toSet();

    final moved = <String>{};
    for (var i = 0; i < currOrder.length; i++) {
      if (!keptSet.contains(i)) moved.add(currOrder[i]);
    }
    return moved;
  }

  static List<int> _longestIncreasingSubsequence(List<int> values) {
    if (values.isEmpty) return const [];
    final n = values.length;
    final tails = <int>[];
    final prev = List<int>.filled(n, -1);

    for (var i = 0; i < n; i++) {
      var lo = 0;
      var hi = tails.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (values[tails[mid]] < values[i]) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0) prev[i] = tails[lo - 1];
      if (lo == tails.length) {
        tails.add(i);
      } else {
        tails[lo] = i;
      }
    }

    final result = <int>[];
    var k = tails.isEmpty ? -1 : tails.last;
    while (k != -1) {
      result.add(k);
      k = prev[k];
    }
    return result.reversed.toList();
  }

  static bool blocksEqual(TextBlockEntity a, TextBlockEntity b) {
    final segsA = List<TextSegment>.of(a.segments);
    final segsB = List<TextSegment>.of(b.segments);
    if (segsA.length != segsB.length) return false;
    for (var i = 0; i < segsA.length; i++) {
      if (segsA[i].text != segsB[i].text) return false;
      if (_formatFlagsOf(segsA[i]) != _formatFlagsOf(segsB[i])) return false;
      if (_urlOf(segsA[i]) != _urlOf(segsB[i])) return false;
    }
    return true;
  }

  static int _formatFlagsOf(TextSegment segment) =>
      segment is FormattedSegment ? segment.format.flags : 0;

  static String? _urlOf(TextSegment segment) =>
      segment is LinkSegment ? segment.url : null;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
