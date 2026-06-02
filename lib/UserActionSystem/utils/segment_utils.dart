// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

/// Splits [segments] at [flatOffset], returning two lists of segments.
///
/// Formatting is preserved: if the split falls in the middle of a segment,
/// that segment is duplicated into two with the same type and format, each
/// carrying its respective portion of the text.
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

/// Returns two cursor positions ordered by their document position:
/// (first, last) where first appears earlier in the document.
/// Returns (null, null) if ordering cannot be determined.
(CursorPositionInTextBlock?, CursorPositionInTextBlock?) orderedCursors(
  DocumentModel document,
  CursorPositionInTextBlock a,
  CursorPositionInTextBlock b,
) {
  if (a.blockId == b.blockId) {
    final block = document.getBlockById(a.blockId);
    if (block is! TextBlock) return (null, null);
    final flatA = block.flatOffsetFromCursor(a.segmentIndex, a.offset);
    final flatB = block.flatOffsetFromCursor(b.segmentIndex, b.offset);
    return flatA <= flatB ? (a, b) : (b, a);
  }

  final ids = document.flatBlockIds();
  final idxA = ids.indexOf(a.blockId);
  final idxB = ids.indexOf(b.blockId);
  if (idxA == -1 || idxB == -1) return (null, null);
  return idxA < idxB ? (a, b) : (b, a);
}

/// Normalizes [segments]: removes empty segments but keeps at least one.
List<TextSegment> normalizeSegments(List<TextSegment> segments) {
  final filtered = segments.where((s) => s.text.isNotEmpty).toList();
  return filtered.isEmpty ? [const TextSegment(text: '')] : filtered;
}
