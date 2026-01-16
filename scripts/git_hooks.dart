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
  Map<Git, UserBackFun> params = {Git.preCommit: _preCommit};
  GitHooks.call(arguments, params);
}

Future<bool> _preCommit() async {
  print('🔄 Lint staged files...');

  final formattingCheckResult = await DartPreCommit.run();
  final allChecksPassed =
      _checkSourceFilesHaveCopyright() && formattingCheckResult.isSuccess;

  if (!allChecksPassed) {
    print('⛔ Commit aborted due to failed checks.');
  } else {
    print('🚀 All pre-commit checks passed.');
  }

  return allChecksPassed;
}

bool _checkSourceFilesHaveCopyright() {
  print('🔄 Check staged files for copyright header...');

  final diffResult = Process.runSync('git', [
    'diff',
    '--cached',
    '--name-only',
    '--diff-filter=ACM',
  ], runInShell: true);

  if (diffResult.exitCode != 0) {
    print('❌ Failed to get git diff: ${diffResult.stderr}');
    return false;
  }

  final stagedFiles = (diffResult.stdout as String)
      .split('\n')
      .where((file) => file.isNotEmpty)
      .toList();

  if (stagedFiles.isEmpty) {
    print('✅ No staged files to check.');
    return true;
  }

  final filesToCheck = stagedFiles.where((filePath) {
    return filePath.startsWith('lib/') || filePath.startsWith('scripts/');
  }).toList();

  if (filesToCheck.isEmpty) {
    print('✅ No staged files in lib or scripts directories.');
    return true;
  }

  final filesWithoutCopyright = filesToCheck.where(
    (filePath) => !checkCopyrightInStagedFile(filePath),
  );

  if (filesWithoutCopyright.isNotEmpty) {
    print('❌ The following files are missing copyright headers:');
    for (var filePath in filesWithoutCopyright) {
      print('- $filePath');
    }
    return false;
  }

  print('✅ All source files have correct copyright header.');
  return true;
}
