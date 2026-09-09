// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

List<String> fetchStagedSourceFiles({List<String> prefixes = const ['lib/', 'scripts/']}) {
  final diffResult = Process.runSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACM'], runInShell: true);

  if (diffResult.exitCode != 0) {
    print('Failed to get git diff: ${diffResult.stderr}');
    return [];
  }

  final stagedFiles = (diffResult.stdout as String).split('\n').where((file) => file.isNotEmpty).where((file) => prefixes.any((prefix) => file.startsWith(prefix))).toList();

  return stagedFiles;
}

List<String> fetchChangedSourceFiles({List<String> prefixes = const ['lib/', 'scripts/']}) {
  final changedFiles = <String>{};

  final diffResult = Process.runSync('git', ['diff', '--name-only', 'HEAD'], runInShell: true);

  if (diffResult.exitCode == 0) {
    changedFiles.addAll((diffResult.stdout as String).split('\n').where((file) => file.isNotEmpty).where((file) => prefixes.any((prefix) => file.startsWith(prefix))));
  }

  final untrackedResult = Process.runSync('git', ['ls-files', '--others', '--exclude-standard'], runInShell: true);

  if (untrackedResult.exitCode == 0) {
    changedFiles.addAll((untrackedResult.stdout as String).split('\n').where((file) => file.isNotEmpty).where((file) => prefixes.any((prefix) => file.startsWith(prefix))));
  }

  return changedFiles.toList();
}
