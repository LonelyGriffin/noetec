// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/document_block.dart';

/// Serializes a list of [TextBlock]s into a markdown string using
/// fenced directives (`:::`) with block attributes.
///
/// Each block is wrapped in a fenced directive carrying the block's ID:
/// ```markdown
/// ::: {#block-id}
/// Text with **bold** and *italic*.
/// :::
/// ```
///
/// If [ranges] is provided, only the specified character range is serialized
/// for each block. [ranges] must have the same length as [blocks]. Each range
/// is a `(fromFlatOffset, toFlatOffset)` pair — half-open interval.
/// Pass `null` entries to serialize the full block.
String blocksToMarkdown(List<TextBlock> blocks, {List<(int, int)?>? ranges}) {
  assert(ranges == null || ranges.length == blocks.length);

  final buffer = StringBuffer();

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final range = ranges?[i];

    List<TextSegment> segments;
    if (range != null) {
      segments = _extractSegmentRange(block.segments.value, range.$1, range.$2);
    } else {
      segments = block.segments.value;
    }

    buffer.writeln('::: {#${block.id}}');
    buffer.writeln(_segmentsToInlineMarkdown(segments));
    buffer.writeln(':::');
    if (i < blocks.length - 1) {
      buffer.writeln();
    }
  }

  return buffer.toString();
}

/// Converts a list of [TextSegment]s to inline markdown text.
String _segmentsToInlineMarkdown(List<TextSegment> segments) {
  final buffer = StringBuffer();

  for (final segment in segments) {
    final text = _escapeMarkdownInline(segment.text);

    switch (segment) {
      case FormattedSegment(:final format):
        final hasBold = format.has(TextFormat.bold);
        final hasItalic = format.has(TextFormat.italic);

        if (hasBold && hasItalic) {
          buffer.write('***$text***');
        } else if (hasBold) {
          buffer.write('**$text**');
        } else if (hasItalic) {
          buffer.write('*$text*');
        } else {
          buffer.write(text);
        }

      case LinkSegment(:final url):
        buffer.write('[${_escapeMarkdownInline(segment.text)}]($url)');

      case TextSegment():
        buffer.write(text);
    }
  }

  return buffer.toString();
}

/// Extracts a sub-range of segments by flat character offsets.
List<TextSegment> _extractSegmentRange(
  List<TextSegment> segments,
  int fromFlat,
  int toFlat,
) {
  final result = <TextSegment>[];
  int offset = 0;

  for (final seg in segments) {
    final segStart = offset;
    final segEnd = offset + seg.text.length;

    if (segEnd <= fromFlat) {
      offset = segEnd;
      continue;
    }
    if (segStart >= toFlat) break;

    final clampStart = (fromFlat - segStart).clamp(0, seg.text.length);
    final clampEnd = (toFlat - segStart).clamp(0, seg.text.length);

    if (clampStart < clampEnd) {
      result.add(seg.cloneWithText(seg.text.substring(clampStart, clampEnd)));
    }

    offset = segEnd;
  }

  return result;
}

/// Escapes characters that have special meaning in markdown inline syntax.
String _escapeMarkdownInline(String text) {
  return text.replaceAllMapped(
    RegExp(r'[\\*_\[\]()~`>#+\-=|{}.!]'),
    (m) => '\\${m[0]}',
  );
}
