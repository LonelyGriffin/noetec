// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'package:git_hooks/install/create_hooks.dart';

/// Script to set up Git hooks for the project. And other first-time setup tasks in the future.
void main() async {
  print('🔄 Setup Git hooks');
  await CreateHooks.copyFile(targetPath: 'scripts/git_hooks.dart');
  print('✅ Git hooks installed');
}
