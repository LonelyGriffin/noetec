// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'run_process.dart';

Future<bool> applyFormatting() => runProcess('dart', ['format', '.'], failMessage: 'Formatting failed.', successMessage: 'Formatting complete.');

Future<bool> checkFormatting() =>
    runProcess('dart', ['format', '--set-exit-if-changed', '.'], failMessage: 'Formatting issues detected.', successMessage: 'All files formatted correctly.');
