// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/IdService/id_service.dart';

/// Parses a markdown string into a list of [TextBlock]s.
///
/// Supports standard markdown paragraphs and Noetec fenced directives:
/// ```markdown
/// ::: {#block-id}
/// Text with **bold** and *italic*.
/// :::
/// ```
///
/// Blocks wrapped in `:::` preserve their ID from the `#id` attribute.
/// Plain paragraphs (without `:::`) get a new ID from [idService].
List<TextBlock> markdownToBlocks(
  String markdown, {
  required IdService idService,
  required String documentId,
}) {
  final document = md.Document(
    blockSyntaxes: [FencedDirectiveSyntax()],
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  final lines = markdown.split('\n');
  final nodes = document.parseLines(lines);

  final blocks = <TextBlock>[];

  for (final node in nodes) {
    if (node is md.Element) {
      if (node.tag == 'noetec-directive') {
        // Fenced directive block with ID.
        final blockId = node.attributes['id'] ?? idService.generateId();
        final segments = _elementChildrenToSegments(node);
        blocks.add(
          TextBlock(
            id: blockId,
            documentId: documentId,
            parent: ValueNotifier(null),
            segments: ListNotifier(
              data: segments.isEmpty ? [const TextSegment(text: '')] : segments,
            ),
          ),
        );
      } else if (node.tag == 'p') {
        // Standard paragraph.
        final segments = _inlineNodesToSegments(node.children ?? []);
        blocks.add(
          TextBlock(
            id: idService.generateId(),
            documentId: documentId,
            parent: ValueNotifier(null),
            segments: ListNotifier(
              data: segments.isEmpty ? [const TextSegment(text: '')] : segments,
            ),
          ),
        );
      }
      // Other block elements (h1, ul, etc.) are ignored for now.
    }
  }

  // Ensure at least one block.
  if (blocks.isEmpty) {
    blocks.add(
      TextBlock(
        id: idService.generateId(),
        documentId: documentId,
        parent: ValueNotifier(null),
        segments: ListNotifier(data: [const TextSegment(text: '')]),
      ),
    );
  }

  return blocks;
}

/// Extracts inline segments from a fenced directive element.
///
/// The directive's children are parsed block-level (may contain `<p>` etc.),
/// so we unwrap one level.
List<TextSegment> _elementChildrenToSegments(md.Element element) {
  final children = element.children ?? [];
  final segments = <TextSegment>[];

  for (final child in children) {
    if (child is md.Element && child.tag == 'p') {
      segments.addAll(_inlineNodesToSegments(child.children ?? []));
    } else {
      // Inline content directly under the directive.
      segments.addAll(_inlineNodesToSegments([child]));
    }
  }

  return segments;
}

/// Converts a list of inline AST nodes into [TextSegment]s.
List<TextSegment> _inlineNodesToSegments(
  List<md.Node> nodes, {
  TextFormat inheritedFormat = TextFormat.none,
}) {
  final segments = <TextSegment>[];

  for (final node in nodes) {
    if (node is md.Text) {
      final text = _unescapeMarkdown(node.text);
      if (text.isEmpty) continue;

      if (inheritedFormat != TextFormat.none) {
        segments.add(FormattedSegment(text: text, format: inheritedFormat));
      } else {
        segments.add(TextSegment(text: text));
      }
    } else if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
          final newFormat = inheritedFormat | TextFormat.bold;
          segments.addAll(
            _inlineNodesToSegments(
              node.children ?? [],
              inheritedFormat: newFormat,
            ),
          );

        case 'em':
          final newFormat = inheritedFormat | TextFormat.italic;
          segments.addAll(
            _inlineNodesToSegments(
              node.children ?? [],
              inheritedFormat: newFormat,
            ),
          );

        case 'a':
          final url = node.attributes['href'] ?? '';
          final text = node.textContent;
          if (text.isNotEmpty) {
            segments.add(LinkSegment(text: _unescapeMarkdown(text), url: url));
          }

        default:
          // For unknown inline elements, extract text content.
          final text = node.textContent;
          if (text.isNotEmpty) {
            if (inheritedFormat != TextFormat.none) {
              segments.add(
                FormattedSegment(
                  text: _unescapeMarkdown(text),
                  format: inheritedFormat,
                ),
              );
            } else {
              segments.add(TextSegment(text: _unescapeMarkdown(text)));
            }
          }
      }
    }
  }

  return segments;
}

/// Unescapes markdown backslash escapes.
String _unescapeMarkdown(String text) {
  return text.replaceAllMapped(
    RegExp(r'\\([\\*_\[\]()~`>#+\-=|{}.!])'),
    (m) => m[1]!,
  );
}

// ---------------------------------------------------------------------------
// FencedDirectiveSyntax — custom block syntax for ::: directives
// ---------------------------------------------------------------------------

/// Parses fenced directive blocks:
/// ```
/// ::: {#block-id}
/// content
/// :::
/// ```
class FencedDirectiveSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => _openPattern;

  static final _openPattern = RegExp(r'^:{3,}\s*\{([^}]*)\}\s*$');
  static final _closePattern = RegExp(r'^:{3,}\s*$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final openMatch = _openPattern.firstMatch(parser.current.content);
    if (openMatch == null) return null;

    final attrString = openMatch.group(1)!.trim();
    final attributes = _parseAttributes(attrString);

    parser.advance(); // Move past the opening fence.

    final childLines = <String>[];
    while (!parser.isDone) {
      if (_closePattern.hasMatch(parser.current.content)) {
        parser.advance(); // Move past the closing fence.
        break;
      }
      childLines.add(parser.current.content);
      parser.advance();
    }

    // Parse the child content as block-level markdown.
    final childContent = childLines.join('\n');
    final childDoc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final childNodes = childDoc.parseLines(childContent.split('\n'));

    final element = md.Element('noetec-directive', childNodes);
    for (final entry in attributes.entries) {
      element.attributes[entry.key] = entry.value;
    }

    return element;
  }

  /// Parses attribute string like `#my-id .class key=value key="quoted"`.
  Map<String, String> _parseAttributes(String attrString) {
    final attrs = <String, String>{};
    final regex = RegExp(
      r'''#([\w-]+)|\.[\w-]+|([\w-]+)=(?:"([^"]*)"|'([^']*)'|([\w-]+))''',
    );

    for (final match in regex.allMatches(attrString)) {
      if (match.group(1) != null) {
        // #id
        attrs['id'] = match.group(1)!;
      } else if (match.group(2) != null) {
        // key=value
        final key = match.group(2)!;
        final value = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
        attrs[key] = value;
      }
    }

    return attrs;
  }
}
