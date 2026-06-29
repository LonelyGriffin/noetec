// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/page/selection.dart';

(List<TextSegment>, List<TextSegment>) splitSegmentsAt(
  List<TextSegment> segments,
  int flatOffset,
) {
  final before = <TextSegment>[];
  final after = <TextSegment>[];
  int remaining = flatOffset;

  for (final seg in segments) {
    final len = seg.text.length;

    if (remaining <= 0) {
      after.add(seg);
    } else if (remaining >= len) {
      before.add(seg);
      remaining -= len;
    } else {
      before.add(seg.cloneWithText(seg.text.substring(0, remaining)));
      after.add(seg.cloneWithText(seg.text.substring(remaining)));
      remaining = 0;
    }
  }

  return (before, after);
}

(CursorPositionInTextBlock?, CursorPositionInTextBlock?) orderedCursors(
  PageEntity page,
  CursorPositionInTextBlock a,
  CursorPositionInTextBlock b,
) {
  if (a.blockId == b.blockId) {
    final block = page.getBlockById(a.blockId);
    if (block is! TextBlockEntity) return (null, null);
    final flatA = block.flatOffsetFromCursor(a.segmentIndex, a.offset);
    final flatB = block.flatOffsetFromCursor(b.segmentIndex, b.offset);
    return flatA <= flatB ? (a, b) : (b, a);
  }

  final ids = page.flatBlockIds();
  final idxA = ids.indexOf(a.blockId);
  final idxB = ids.indexOf(b.blockId);
  if (idxA == -1 || idxB == -1) return (null, null);
  return idxA < idxB ? (a, b) : (b, a);
}

List<TextSegment> normalizeSegments(List<TextSegment> segments) {
  final filtered = segments.where((s) => s.text.isNotEmpty).toList();
  return filtered.isEmpty ? [const TextSegment(text: '')] : filtered;
}
