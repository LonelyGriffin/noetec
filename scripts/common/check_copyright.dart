// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print

import 'dart:io';

const _doubleSlashCopyrightText ='''
// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
''';

const fileTypeToExpectCopyright = {
  'dart': _doubleSlashCopyrightText,
};

List<String> findFilesWithoutCopyright(String folderPath) {
  List<String> filesWithoutCopyright = [];

  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    print('Directory does not exist: $folderPath');
    return filesWithoutCopyright;
  }

  final folderContent = directory.listSync(recursive: true);

  filesWithoutCopyright.addAll(folderContent
    .whereType<File>()
    .map((file) => file.path)
    .where((filePath) {
      final fileExtension = filePath.split('.').last;
      if (!fileTypeToExpectCopyright.containsKey(fileExtension)) {
        return false;
      }
      final expectCopyrightText = fileTypeToExpectCopyright[fileExtension];
      if (expectCopyrightText == null) {
        return false;
      }
      return !hasCopyrightInFile(filePath, expectCopyrightText);
    })
  );

  final subFolders = folderContent.whereType<Directory>();

  for (var subFolder in subFolders) {
    filesWithoutCopyright.addAll(findFilesWithoutCopyright(subFolder.path));
  }

  return filesWithoutCopyright;
}

bool checkCopyrightInFile(String filePath) {
  final fileExtension = filePath.split('.').last;
  final expectCopyrightText = fileTypeToExpectCopyright[fileExtension];

  if (expectCopyrightText == null) {
    return true;
  }

  return hasCopyrightInFile(filePath, expectCopyrightText);
}

bool hasCopyrightInFile(String filePath, String expectCopyrightText) {
  try {
    final fileContent = File(filePath).readAsStringSync();
    
    return fileContent.startsWith(expectCopyrightText);
  } catch (e) {
    print('Error reading file $filePath: $e');
    return false;
  }
}

bool checkCopyrightInStagedFile(String filePath) {
  final fileExtension = filePath.split('.').last;
  final expectCopyrightText = fileTypeToExpectCopyright[fileExtension];

  if (expectCopyrightText == null) {
    return true;
  }

  return hasCopyrightInStagedFile(filePath, expectCopyrightText);
}

bool hasCopyrightInStagedFile(String filePath, String expectCopyrightText) {
  try {
     final indexContentResult = Process.runSync(
      'git',
      ['show', ':$filePath'],
      runInShell: true,
    );

    final fileContent = indexContentResult.stdout as String;
    
    return fileContent.startsWith(expectCopyrightText);
  } catch (e) {
    print('Error reading file $filePath: $e');
    return false;
  }
}