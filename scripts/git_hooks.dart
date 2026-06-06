// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import "dart:io";

import "package:dart_pre_commit/dart_pre_commit.dart";
import "package:git_hooks/git_hooks.dart";

import "common/check_copyright.dart";

/// Script entry point for git hooks.
/// See [git_hooks] package docs for more details.
void main(List arguments) {
  final params = {Git.preCommit: _preCommit};
  GitHooks.call(arguments, params);
}

Future<bool> _preCommit() async {
  print('🔄 Lint staged files...');

  final formattingCheckResult = await DartPreCommit.run();
  final allChecksPassed = _checkSourceFilesHaveCopyright() && formattingCheckResult.isSuccess;

  if (!allChecksPassed) {
    print('⛔ Commit aborted due to failed checks.');
  } else {
    print('🚀 All pre-commit checks passed.');
  }

  return allChecksPassed;
}

bool _checkSourceFilesHaveCopyright() {
  print('Check staged files for copyright header...');

  final diffResult = Process.runSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACM'], runInShell: true);

  if (diffResult.exitCode != 0) {
    print('Failed to get git diff: ${diffResult.stderr}');
    return false;
  }

  final stagedFiles = (diffResult.stdout as String).split('\n').where((file) => file.isNotEmpty).where((file) => file.startsWith('lib/') || file.startsWith('scripts/')).toList();

  if (stagedFiles.isEmpty) {
    print('No staged files to check.');
    return true;
  }

  final failed = <String>[];
  for (final filePath in stagedFiles) {
    if (!checkCopyrightInStagedFile(filePath)) {
      failed.add(filePath);
    }
  }

  if (failed.isNotEmpty) {
    print('Files missing copyright headers:');
    for (final file in failed) {
      print('- $file');
    }
    return false;
  }

  print('All source files have correct copyright header.');
  return true;
}
