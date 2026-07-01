// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:path/path.dart' as p;

class ExternalEditHandler {
  ExternalEditHandler({
    required IFileSystemService fileSystem,
    required MarkdownSystem markdownSystem,
    required OpLogSystem oplogSystem,
    required String vaultRootPath,
  }) : _fileSystem = fileSystem,
       _markdownSystem = markdownSystem,
       _oplogSystem = oplogSystem,
       _vaultRootPath = vaultRootPath;

  final IFileSystemService _fileSystem;
  final MarkdownSystem _markdownSystem;
  final OpLogSystem _oplogSystem;
  final String _vaultRootPath;

  Future<String?> handleExternalEdit(
    String relativePath,
    String? knownPageId,
  ) async {
    final absolutePath = p.join(_vaultRootPath, relativePath);
    if (!await _fileSystem.fileExists(absolutePath)) return null;

    final raw = await _fileSystem.readFile(absolutePath);
    final (:frontmatter, :content) = PageFrontmatterCodec.parse(raw);

    final blocks = _markdownSystem.parseMarkdown(content);
    final pageId = knownPageId ?? frontmatter.id;

    final currentHash =
        'sha256:${PageFrontmatterCodec.computeContentHash(content)}';

    await _oplogSystem.recordExternalEdit(
      relativePath,
      blocks,
      currentHash,
      pageId: pageId,
    );

    final updatedFrontmatter = frontmatter.copyWith(
      contentHash: currentHash,
      modified: DateTime.now().toUtc(),
    );
    final newContent = PageFrontmatterCodec.encode(updatedFrontmatter, content);
    await _fileSystem.writeFile(absolutePath, newContent);

    return pageId;
  }

  List<TextBlockEntity> parseBlocks(String rawContent) {
    final (:frontmatter, :content) = PageFrontmatterCodec.parse(rawContent);
    return _markdownSystem.parseMarkdown(content);
  }
}
