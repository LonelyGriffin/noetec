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

    for (int i = 0; i < segmentIndex; i++) {
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
    if (segs.isEmpty) {
      return CursorPositionInTextBlock(blockId: id, offset: 0, segmentIndex: 0);
    }

    int remaining = flatOffset;
    for (var i = 0; i < segs.length; i++) {
      final len = segs[i].text.length;
      // Cursor can sit anywhere from 0 to len (inclusive) inside a segment,
      // but only at position 0 of the NEXT segment when remaining == len
      // and there IS a next segment — so we let the loop continue.
      if (remaining <= len) {
        return CursorPositionInTextBlock(
          blockId: id,
          offset: remaining,
          segmentIndex: i,
        );
      }
      remaining -= len;
    }
    // Beyond end: clamp to last segment's end.
    return CursorPositionInTextBlock(
      blockId: id,
      offset: segs.last.text.length,
      segmentIndex: segs.length - 1,
    );
  }

  /// Resolves the segment and local offset of the **character** at
  /// [flatOffset]. Unlike [cursorPosFromFlatOffset], this never returns an
  /// offset equal to a segment's length — when the flat offset falls at a
  /// segment boundary it advances to offset 0 of the next segment.
  ///
  /// Returns `null` if [flatOffset] is out of range (negative or >= total
  /// length).
  CursorPositionInTextBlock? charPosFromFlatOffset(int flatOffset) {
    final segs = segments.value;
    if (segs.isEmpty || flatOffset < 0) return null;

    int remaining = flatOffset;
    for (var i = 0; i < segs.length; i++) {
      final len = segs[i].text.length;
      if (remaining < len) {
        return CursorPositionInTextBlock(
          blockId: id,
          offset: remaining,
          segmentIndex: i,
        );
      }
      remaining -= len;
    }
    // flatOffset >= totalLength — out of range.
    return null;
  }

  /// Returns the flat-offset range `(start, end)` of the word at
  /// [flatOffset].
  ///
  /// A "word" is a contiguous run of alphanumeric / underscore characters.
  /// If [flatOffset] lands on a non-word character (space, punctuation) the
  /// returned range covers that single character.
  ///
  /// [flatOffset] is clamped to `[0, totalLength]`.  When the block is empty
  /// `(0, 0)` is returned.
  (int, int) wordBoundaryAt(int flatOffset) {
    final text = computeAllSegmentsText();
    if (text.isEmpty) return (0, 0);

    final length = text.length;
    final clamped = flatOffset.clamp(0, length);

    // When sitting exactly at the end, treat the last character as the target.
    final charIndex = clamped >= length ? length - 1 : clamped;

    if (_isWordChar(text.codeUnitAt(charIndex))) {
      // Expand to the left while word characters.
      int start = charIndex;
      while (start > 0 && _isWordChar(text.codeUnitAt(start - 1))) {
        start--;
      }
      // Expand to the right while word characters.
      int end = charIndex + 1;
      while (end < length && _isWordChar(text.codeUnitAt(end))) {
        end++;
      }
      return (start, end);
    } else {
      // Non-word character: select only that character.
      return (charIndex, charIndex + 1);
    }
  }

  /// Returns `true` for characters that are considered part of a "word":
  /// letters, digits, and underscore.
  static bool _isWordChar(int codeUnit) {
    // 0-9
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return true;
    // A-Z
    if (codeUnit >= 0x41 && codeUnit <= 0x5A) return true;
    // a-z
    if (codeUnit >= 0x61 && codeUnit <= 0x7A) return true;
    // underscore
    if (codeUnit == 0x5F) return true;
    return false;
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
  italic(1 << 1),
  boldItalic(1 << 0 | 1 << 1);

  const TextFormat(this.value);

  final int value;

  /// Combines this format with [other] using bitwise OR.
  TextFormat operator |(TextFormat other) => fromFlags(value | other.value);

  /// Returns `true` if this format includes [flag].
  bool has(TextFormat flag) => value & flag.value != 0;

  /// Looks up the [TextFormat] enum value for the given bitmask.
  static TextFormat fromFlags(int flags) {
    for (final fmt in TextFormat.values) {
      if (fmt.value == flags) return fmt;
    }
    return TextFormat.none;
  }
}
