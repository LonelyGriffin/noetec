// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'run_process.dart';

/// Directories passed to `dart format`.
///
/// Scoped to the project's source directories instead of the whole repo root:
/// `dart format .` walks every directory under the repo root, including the
/// gitignored Multica/Hermes task artifacts under `noetec-ai-*/` (full nested
/// worktrees with hundreds of `.dart` files). Formatting those rewrites other
/// tasks' working trees, so we scope it the same way `dart analyze` is scoped.
const sourceDirectories = ['lib', 'test', 'integration_test', 'scripts'];

Future<bool> applyFormatting() => runProcess('dart', ['format', ...sourceDirectories], failMessage: 'Formatting failed.', successMessage: 'Formatting complete.');

Future<bool> checkFormatting() =>
    runProcess('dart', ['format', '--set-exit-if-changed', ...sourceDirectories], failMessage: 'Formatting issues detected.', successMessage: 'All files formatted correctly.');
