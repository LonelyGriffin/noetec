// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class PageNameConflictException implements Exception {
  final String fileName;

  const PageNameConflictException(this.fileName);

  @override
  String toString() =>
      'PageNameConflictException: page "$fileName" already exists';
}

sealed class PageFileNode {
  const PageFileNode();
  String get name;
}

final class PageFileFolder extends PageFileNode {
  @override
  final String name;
  final List<PageFileNode> children;

  const PageFileFolder({required this.name, this.children = const []});
}

final class PageFileItem extends PageFileNode {
  @override
  final String name;
  final String relativePath;
  final String pageId;
  final DateTime? modified;

  const PageFileItem({
    required this.name,
    required this.relativePath,
    required this.pageId,
    this.modified,
  });
}

class VaultFileService {
  VaultFileService(this._fileSystem, this._vaultSystem, this._pageSystem) {
    _vaultSystem.currentVault.addListener(_onVaultChanged);
    _pageSystem.activePageId.addListener(_onActivePageChanged);
  }

  final IFileSystemService _fileSystem;
  final VaultSystem _vaultSystem;
  final PageSystem _pageSystem;
  final fileTree = ListNotifier<PageFileNode>();
  final renamingPath = ValueNotifier<String?>(null);
  final selectedPagePath = ValueNotifier<String?>(null);

  static const _uuid = Uuid();

  void _onActivePageChanged() {
    selectedPagePath.value = null;
  }

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      renamingPath.value = null;
      selectedPagePath.value = null;
      unawaited(scanFileTree(vault.rootPath));
    } else {
      fileTree.clear();
      renamingPath.value = null;
      selectedPagePath.value = null;
    }
  }

  Future<void> scanFileTree(String vaultRootPath) async {
    final pagesDir = p.join(vaultRootPath, 'pages');
    final nodes = await _scanDirectory(pagesDir, vaultRootPath);
    fileTree
      ..clear()
      ..addAll(nodes);
  }

  Future<List<PageFileNode>> _scanDirectory(
    String directoryPath,
    String rootPath,
  ) async {
    if (!await _fileSystem.directoryExists(directoryPath)) return [];

    final entries = await _fileSystem.listDirectory(directoryPath);
    final children = <PageFileNode>[];

    for (final entry in entries) {
      if (entry.name.startsWith('.')) continue;

      if (entry.isDirectory) {
        final subChildren = await _scanDirectory(entry.path, rootPath);
        children.add(PageFileFolder(name: entry.name, children: subChildren));
      } else if (entry.name.endsWith('.md')) {
        final relativePath = p
            .relative(entry.path, from: rootPath)
            .replaceAll('\\', '/');
        String pageId = '';
        try {
          final raw = await _fileSystem.readFile(entry.path);
          final parsed = PageFrontmatterCodec.parse(raw);
          pageId = parsed.frontmatter.id;
        } catch (_) {
          pageId = _uuid.v4();
        }
        children.add(
          PageFileItem(
            name: entry.name,
            relativePath: relativePath,
            pageId: pageId,
            modified: entry.lastModified,
          ),
        );
      }
    }

    children.sort((a, b) {
      if (a is PageFileFolder && b is PageFileItem) return -1;
      if (a is PageFileItem && b is PageFileFolder) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return children;
  }

  Future<String> createPage(String vaultRootPath) async {
    final pagesDir = p.join(vaultRootPath, 'pages');
    final name = await _generateUniquePageName(pagesDir);
    final filePath = p.join(pagesDir, name);

    final blockId = _uuid.v4();
    final content = '::: {#$blockId}\n\n:::\n';
    final hash = PageFrontmatterCodec.computeContentHash(content);
    final frontmatter = PageFrontmatter(
      id: _uuid.v4(),
      contentHash: 'sha256:$hash',
      modified: DateTime.now().toUtc(),
    );
    final fileContent = PageFrontmatterCodec.encode(frontmatter, content);
    await _fileSystem.writeFile(filePath, fileContent);

    await scanFileTree(vaultRootPath);

    final relativePath = p
        .relative(filePath, from: vaultRootPath)
        .replaceAll('\\', '/');
    return relativePath;
  }

  Future<String> renamePage(
    String vaultRootPath,
    String oldRelativePath,
    String newFileName,
  ) async {
    var finalName = newFileName;
    if (!finalName.endsWith('.md')) {
      finalName = '$finalName.md';
    }

    final oldFileName = p.basename(oldRelativePath);
    if (finalName == oldFileName) return oldRelativePath;

    final oldAbsolutePath = p.normalize(p.join(vaultRootPath, oldRelativePath));
    final newAbsolutePath = p.normalize(
      p.join(p.dirname(oldAbsolutePath), finalName),
    );

    if (await _fileSystem.fileExists(newAbsolutePath)) {
      throw PageNameConflictException(finalName);
    }

    await _fileSystem.renameFileOrDirectory(oldAbsolutePath, newAbsolutePath);
    await scanFileTree(vaultRootPath);

    final newRelativePath = p
        .relative(newAbsolutePath, from: vaultRootPath)
        .replaceAll('\\', '/');
    return newRelativePath;
  }

  Future<String> _generateUniquePageName(String pagesDir) async {
    const baseName = 'untitled.md';
    if (!await _fileSystem.fileExists(p.join(pagesDir, baseName))) {
      return baseName;
    }
    var counter = 1;
    while (true) {
      final candidate = 'untitled-$counter.md';
      if (!await _fileSystem.fileExists(p.join(pagesDir, candidate))) {
        return candidate;
      }
      counter++;
    }
  }

  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    _pageSystem.activePageId.removeListener(_onActivePageChanged);
    renamingPath.dispose();
    selectedPagePath.dispose();
    fileTree.dispose();
  }
}
