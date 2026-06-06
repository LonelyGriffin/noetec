// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print

import 'dart:io';

const _doubleSlashCopyrightText = '''
// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
''';

const fileTypeToExpectCopyright = {'dart': _doubleSlashCopyrightText};

bool checkCopyrightInFiles(List<String> filePaths) {
  final failed = filePaths.where((path) {
    final ext = path.split('.').last;
    final expected = fileTypeToExpectCopyright[ext];
    if (expected == null) return false;
    return !hasCopyrightInFile(path, expected);
  }).toList();

  if (failed.isNotEmpty) {
    print('❌ Files missing copyright headers:');
    for (final file in failed) {
      print('  • $file');
    }
    return false;
  }
  print('✅ All source files have correct copyright header');
  return true;
}

void ensureCopyrightInFiles(List<String> filePaths) {
  print('🔄 Ensure copyright');
  for (final filePath in filePaths) {
    final ext = filePath.split('.').last;
    final expected = fileTypeToExpectCopyright[ext];
    if (expected == null) continue;
    if (hasCopyrightInFile(filePath, expected)) continue;

    final file = File(filePath);
    final content = file.readAsStringSync();
    file.writeAsStringSync('$expected$content');
    print('➕ Added copyright: $filePath');
  }
  print('✅ All source files have correct copyright header');
}

List<String> findFilesWithoutCopyright(String folderPath) {
  final filesWithoutCopyright = <String>[];

  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    print('❌ Directory does not exist: $folderPath');
    return filesWithoutCopyright;
  }

  final folderContent = directory.listSync(recursive: true);

  filesWithoutCopyright.addAll(
    folderContent.whereType<File>().map((file) => file.path).where((filePath) {
      final fileExtension = filePath.split('.').last;
      if (!fileTypeToExpectCopyright.containsKey(fileExtension)) {
        return false;
      }
      final expectCopyrightText = fileTypeToExpectCopyright[fileExtension];
      if (expectCopyrightText == null) {
        return false;
      }
      return !hasCopyrightInFile(filePath, expectCopyrightText);
    }),
  );

  return filesWithoutCopyright;
}

bool hasCopyrightInFile(String filePath, String expectCopyrightText) {
  try {
    final fileContent = File(filePath).readAsStringSync().replaceAll('\r\n', '\n');

    return fileContent.startsWith(expectCopyrightText);
  } catch (e) {
    print('❌ Error reading file $filePath: $e');
    return false;
  }
}
