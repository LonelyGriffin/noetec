// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

final class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final DateTime? lastModified;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.lastModified,
  });
}

abstract interface class IFileSystemService {
  Future<bool> directoryExists(String path);

  Future<void> createDirectory(String path);

  Future<String> readFile(String path);

  Future<void> writeFile(String path, String content);

  Future<bool> fileExists(String path);

  Future<String?> pickDirectory();

  Future<List<FileEntry>> listDirectory(String path);

  Future<void> deleteFile(String path);

  Future<void> renameFileOrDirectory(String oldPath, String newPath);

  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  });

  Future<void> appendToFile(String path, String content);
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

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final dir = Directory(path);
    final entries = await dir.list().toList();
    return [
      for (final entry in entries)
        if (entry is Directory)
          FileEntry(
            name: p.basename(entry.path),
            path: entry.path,
            isDirectory: true,
          )
        else if (entry is File)
          FileEntry(
            name: p.basename(entry.path),
            path: entry.path,
            isDirectory: false,
            lastModified: await entry.lastModified(),
          ),
    ];
  }

  @override
  Future<void> deleteFile(String path) => File(path).delete();

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      await oldFile.rename(newPath);
      return;
    }
    final oldDir = Directory(oldPath);
    if (await oldDir.exists()) {
      await oldDir.rename(newPath);
    }
  }

  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) {
    late StreamController<FileEntry> controller;
    Timer? timer;
    final lastModified = <String, DateTime>{};

    Future<void> poll() async {
      final dir = Directory(path);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true)) {
        final stat = await entity.stat();
        final entryPath = entity.path;
        final prev = lastModified[entryPath];
        if (prev == null || stat.modified.isAfter(prev)) {
          lastModified[entryPath] = stat.modified;
          if (prev != null) {
            controller.add(
              FileEntry(
                name: p.basename(entryPath),
                path: entryPath,
                isDirectory: entity is Directory,
                lastModified: stat.modified,
              ),
            );
          }
        }
      }
    }

    controller = StreamController<FileEntry>(
      onListen: () {
        poll();
        timer = Timer.periodic(pollInterval, (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Future<void> appendToFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content, mode: FileMode.append, encoding: utf8);
  }
}
