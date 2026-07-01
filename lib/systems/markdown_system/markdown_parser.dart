// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:markdown/markdown.dart' as md;
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/service/id_service.dart';

List<TextBlockEntity> markdownToBlocks(
  String markdown, {
  required IIdService idService,
  String? parentId,
}) {
  final document = md.Document(
    blockSyntaxes: [FencedDirectiveSyntax()],
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  final lines = markdown.split('\n');
  final nodes = document.parseLines(lines);

  final blocks = <TextBlockEntity>[];

  for (final node in nodes) {
    if (node is md.Element) {
      if (node.tag == 'noetec-directive') {
        final blockId = node.attributes['id'] ?? idService.generateId();
        final segments = _elementChildrenToSegments(node);
        blocks.add(
          TextBlockEntity(
            id: blockId,
            parentId: parentId,
            segments: segments.isEmpty
                ? [const TextSegment(text: '')]
                : segments,
          ),
        );
      } else if (node.tag == 'p') {
        final segments = _inlineNodesToSegments(node.children ?? []);
        blocks.add(
          TextBlockEntity(
            id: idService.generateId(),
            parentId: parentId,
            segments: segments.isEmpty
                ? [const TextSegment(text: '')]
                : segments,
          ),
        );
      }
    }
  }

  if (blocks.isEmpty) {
    blocks.add(
      TextBlockEntity(
        id: idService.generateId(),
        parentId: parentId,
        segments: [const TextSegment(text: '')],
      ),
    );
  }

  return blocks;
}

List<TextSegment> _elementChildrenToSegments(md.Element element) {
  final children = element.children ?? [];
  final segments = <TextSegment>[];

  for (final child in children) {
    if (child is md.Element && child.tag == 'p') {
      segments.addAll(_inlineNodesToSegments(child.children ?? []));
    } else {
      segments.addAll(_inlineNodesToSegments([child]));
    }
  }

  return segments;
}

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

String _unescapeMarkdown(String text) {
  return text.replaceAllMapped(
    RegExp(r'\\([\\*_\[\]()~`>#+\-=|{}.!])'),
    (m) => m[1]!,
  );
}

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

    parser.advance();

    final childLines = <String>[];
    while (!parser.isDone) {
      if (_closePattern.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      childLines.add(parser.current.content);
      parser.advance();
    }

    final childContent = childLines.join('\n');
    final childDoc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final childNodes = childDoc.parseLines(childContent.split('\n'));

    final element = md.Element('noetec-directive', childNodes);
    for (final entry in attributes.entries) {
      element.attributes[entry.key] = entry.value;
    }

    return element;
  }

  Map<String, String> _parseAttributes(String attrString) {
    final attrs = <String, String>{};
    final regex = RegExp(
      r'''#([\w-]+)|\.[\w-]+|([\w-]+)=(?:"([^"]*)"|'([^']*)'|([\w-]+))''',
    );

    for (final match in regex.allMatches(attrString)) {
      if (match.group(1) != null) {
        attrs['id'] = match.group(1)!;
      } else if (match.group(2) != null) {
        final key = match.group(2)!;
        final value = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
        attrs[key] = value;
      }
    }

    return attrs;
  }
}
