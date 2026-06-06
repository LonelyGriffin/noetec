// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import "package:dart_pre_commit/dart_pre_commit.dart";
import "package:git_hooks/git_hooks.dart";

import "common/changed_files.dart";
import "common/check_copyright.dart";

/// Script entry point for git hooks.
/// See [git_hooks] package docs for more details.
void main(List arguments) {
  final params = {Git.preCommit: _preCommit};
  GitHooks.call(arguments, params);
}

Future<bool> _preCommit() async {
  print('🔄 Linting staged files...');

  final formattingCheckResult = await DartPreCommit.run();
  final stagedFiles = fetchStagedSourceFiles();
  final copyrightCheckResult = checkCopyrightInFiles(stagedFiles);
  final allChecksPassed = formattingCheckResult.isSuccess && copyrightCheckResult;

  if (!allChecksPassed) {
    print('🛑 Commit aborted due to failed checks');
  } else {
    print('🚀 All pre-commit checks passed');
  }

  return allChecksPassed;
}
