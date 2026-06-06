// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract interface class IFileSystemService {
  Future<bool> directoryExists(String path);

  Future<void> createDirectory(String path);

  Future<String> readFile(String path);

  Future<void> writeFile(String path, String content);

  Future<bool> fileExists(String path);

  Future<String?> pickDirectory();
}

class FileSystemServiceImpl implements IFileSystemService {
  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);

  @override
  Future<String> readFile(String path) => File(path).readAsString();

  @override
  Future<void> writeFile(String path, String content) =>
      File(path).writeAsString(content);

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();
}
