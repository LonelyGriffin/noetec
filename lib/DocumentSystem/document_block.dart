// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

abstract class Block {
  final String id;
  final String documentId;
  ValueNotifier<Block?> parent;

  Block({required this.documentId, required this.id, required this.parent});

  void dispose() {}
}

abstract class ContainerBlock extends Block {
  final ListNotifier<Block> children;

  ContainerBlock({
    required super.documentId,
    required super.id,
    required super.parent,
    required this.children,
  });

  @override
  void dispose() {
    children.dispose();
    super.dispose();
  }
}

class TextBlock extends Block {
  final ListNotifier<TextSegment> segments;

  TextBlock({
    required super.documentId,
    required super.id,
    required super.parent,
    required this.segments,
  });

  String computeAllSegmentsText() => segments.value.map((s) => s.text).join();

  int computeAllSegmentsOffset(int segmentIndex, int offset) {
    var result = 0;

    for (int i = 0; i < segmentIndex; i++)
    {
      result += segments[i].text.length;
    }

    return result + offset;
  }

  /// Converts a (segmentIndex, offset) cursor position to a flat character
  /// offset within [flatText].
  int flatOffsetFromCursor(int segmentIndex, int offset) {
    int flat = 0;
    final segs = segments.value;
    for (var i = 0; i < segmentIndex && i < segs.length; i++) {
      flat += segs[i].text.length;
    }
    return flat + offset;
  }

  /// Converts a flat character offset within all segments text to a
  /// (segmentIndex, offset) cursor position.
  ///
  /// If [flatOffset] is beyond the total text length it is clamped to the end
  /// of the last segment.
  CursorPositionInTextBlock cursorPosFromFlatOffset(int flatOffset) {
    final segs = segments.value;
    if (segs.isEmpty) return CursorPositionInTextBlock(blockId: id, offset: 0, segmentIndex: 0);

    int remaining = flatOffset;
    for (var i = 0; i < segs.length; i++) {
      final len = segs[i].text.length;
      // Cursor can sit anywhere from 0 to len (inclusive) inside a segment,
      // but only at position 0 of the NEXT segment when remaining == len
      // and there IS a next segment — so we let the loop continue.
      if (remaining <= len) {
        return CursorPositionInTextBlock(blockId: id, offset: remaining, segmentIndex: i);
      }
      remaining -= len;
    }
    // Beyond end: clamp to last segment's end.
    return CursorPositionInTextBlock(blockId: id, offset: segs.last.text.length, segmentIndex: segs.length - 1);
  }

  @override
  void dispose() {
    segments.dispose();
    super.dispose();
  }
}

@immutable
class TextSegment {
  final String text;

  const TextSegment({required this.text});

  TextSegment cloneWithText(String text) {
    return TextSegment(text: text);
  }
}

@immutable
class FormattedSegment extends TextSegment {
  final TextFormat format;

  const FormattedSegment({required super.text, required this.format});

  @override
  FormattedSegment cloneWithText(String text) {
    return FormattedSegment(text: text, format: format);
  }
}

@immutable
class LinkSegment extends TextSegment {
  final String url;

  const LinkSegment({required super.text, required this.url});

  @override
  LinkSegment cloneWithText(String text) {
    return LinkSegment(text: text, url: url);
  }
}

enum TextFormat {
  none(0),
  bold(1 << 0),
  italic(1 << 1);

  const TextFormat(this.value);

  final int value;
}
