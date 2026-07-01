// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

import 'common/changed_files.dart';
import 'common/check_copyright.dart';
import 'common/format_runner.dart';

Future<void> main() async {
  final changedFiles = fetchChangedSourceFiles();
  ensureCopyrightInFiles(changedFiles);
  print('🔄 Format');
  final success = await applyFormatting();
  exit(success ? 0 : 1);
}
