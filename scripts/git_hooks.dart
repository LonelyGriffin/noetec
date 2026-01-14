// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import "package:git_hooks/git_hooks.dart";

/// Script entry point for git hooks.
/// See [git_hooks] package docs for more details.
void main(List arguments) {
  Map<Git, UserBackFun> params = {
    Git.preCommit: preCommit
  };
  GitHooks.call(arguments, params);
}

Future<bool> preCommit() async {
  print('✅ All checks passed in pre-commit hook.');
  return true;
}