import 'dart:io';

import 'package:path/path.dart' as p;

class VaultFolderFixture {
  final String rootPath;
  final Directory _tempDir;

  VaultFolderFixture._({required this.rootPath, required Directory tempDir})
    : _tempDir = tempDir;

  static Future<VaultFolderFixture> fromFixture(String fixtureName) async {
    final temp = Directory.systemTemp.createTempSync('noetec_e2e_');
    await _copyDirectory(Directory('test_data/fixtures/$fixtureName'), temp);
    return VaultFolderFixture._(rootPath: temp.path, tempDir: temp);
  }

  static Future<VaultFolderFixture> createEmpty() async {
    final temp = Directory.systemTemp.createTempSync('noetec_e2e_parent_');
    return VaultFolderFixture._(rootPath: temp.path, tempDir: temp);
  }

  Future<String> readFile(String relativePath) =>
      File(p.join(rootPath, relativePath)).readAsString();

  Future<bool> fileExists(String relativePath) =>
      File(p.join(rootPath, relativePath)).exists();

  Future<List<String>> listPages() async {
    final pagesDir = Directory(p.join(rootPath, 'pages'));
    if (!await pagesDir.exists()) return [];
    return (await pagesDir.list(recursive: true).toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => p.relative(f.path, from: rootPath))
        .toList();
  }

  Future<void> dispose() => _tempDir.delete(recursive: true);
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  if (!await destination.exists()) {
    await destination.create(recursive: true);
  }
  await for (final entity in source.list()) {
    final newPath = p.join(destination.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(newPath));
    }
  }
}
