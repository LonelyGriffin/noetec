// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:listen_it/listen_it.dart';
import 'package:noetec/entity/page/block/block.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/page/selection.dart';

class TextBlockEntity extends BlockEntity {
  final ListNotifier<TextSegment> segments;

  TextBlockEntity({
    required super.id,
    super.parentId,
    List<TextSegment>? segments,
  }) : segments = ListNotifier(data: segments ?? [const TextSegment(text: '')]);

  String computeAllSegmentsText() {
    final buffer = StringBuffer();
    for (final segment in segments) {
      buffer.write(segment.text);
    }
    return buffer.toString();
  }

  int flatOffsetFromCursor(int segmentIndex, int offset) {
    var flatOffset = 0;
    for (var i = 0; i < segmentIndex && i < segments.length; i++) {
      flatOffset += segments[i].text.length;
    }
    return flatOffset + offset;
  }

  CursorPositionInTextBlock cursorPosFromFlatOffset(int flatOffset) {
    var remaining = flatOffset;
    for (var i = 0; i < segments.length; i++) {
      final segLen = segments[i].text.length;
      if (remaining <= segLen) {
        return CursorPositionInTextBlock(
          blockId: id,
          segmentIndex: i,
          offset: remaining,
        );
      }
      remaining -= segLen;
    }
    return CursorPositionInTextBlock(
      blockId: id,
      segmentIndex: segments.length - 1,
      offset: segments.last.text.length,
    );
  }

  ({int segmentIndex, int offset})? charPosFromFlatOffset(int flatOffset) {
    var remaining = flatOffset;
    for (var i = 0; i < segments.length; i++) {
      final segLen = segments[i].text.length;
      if (remaining < segLen) {
        return (segmentIndex: i, offset: remaining);
      }
      remaining -= segLen;
    }
    return null;
  }

  (int, int) wordBoundaryAt(int flatOffset) {
    final fullText = computeAllSegmentsText();
    if (fullText.isEmpty) return (0, 0);

    final clampedOffset = flatOffset.clamp(0, fullText.length);

    final wordRegex = RegExp(r'\w+');
    for (final match in wordRegex.allMatches(fullText)) {
      if (match.start <= clampedOffset && clampedOffset < match.end) {
        return (match.start, match.end);
      }
    }

    return (clampedOffset, clampedOffset);
  }

  @override
  void dispose() {
    segments.dispose();
    super.dispose();
  }
}
