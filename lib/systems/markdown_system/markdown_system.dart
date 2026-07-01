// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/markdown_system/markdown_parser.dart' as parser;
import 'package:noetec/systems/markdown_system/markdown_serializer.dart'
    as serializer;

class MarkdownSystem {
  final IIdService idService;

  MarkdownSystem(this.idService);

  List<TextBlockEntity> parseMarkdown(String markdown, {String? parentId}) {
    return parser.markdownToBlocks(
      markdown,
      idService: idService,
      parentId: parentId,
    );
  }

  String serializeBlocks(
    List<TextBlockEntity> blocks, {
    List<(int, int)?>? ranges,
  }) {
    return serializer.blocksToMarkdown(blocks, ranges: ranges);
  }
}
