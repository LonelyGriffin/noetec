// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:path/path.dart' as p;

class MergeApplier {
  MergeApplier({
    required IFileSystemService fileSystem,
    required MarkdownSystem markdownSystem,
    required String vaultRootPath,
  }) : _fileSystem = fileSystem,
       _markdownSystem = markdownSystem,
       _vaultRootPath = vaultRootPath;

  final IFileSystemService _fileSystem;
  final MarkdownSystem _markdownSystem;
  final String _vaultRootPath;

  Future<({String fileHash, String content})> applyToDisk(
    String relativePath,
    List<ReconstructedBlock> blocks,
  ) async {
    final textBlocks = blocks
        .map(
          (rb) =>
              TextBlockEntity(id: rb.blockId, segments: rb.segments.toList()),
        )
        .toList();

    final markdown = _markdownSystem.serializeBlocks(textBlocks);
    final hash = PageFrontmatterCodec.computeContentHash(markdown);

    final absolutePath = p.join(_vaultRootPath, relativePath);
    final existingRaw = await _fileSystem.readFile(absolutePath);
    final (:frontmatter, :content) = PageFrontmatterCodec.parse(existingRaw);

    final updatedFrontmatter = frontmatter.copyWith(
      contentHash: 'sha256:$hash',
      modified: DateTime.now().toUtc(),
    );

    final fileContent = PageFrontmatterCodec.encode(
      updatedFrontmatter,
      markdown,
    );
    await _fileSystem.writeFile(absolutePath, fileContent);

    return (fileHash: 'sha256:$hash', content: markdown);
  }

  List<TextBlockEntity> blocksFromReconstructed(
    List<ReconstructedBlock> blocks,
  ) => blocks
      .map(
        (rb) => TextBlockEntity(id: rb.blockId, segments: rb.segments.toList()),
      )
      .toList();
}
