// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/common/path_audit.dart';

void main() {
  test('path audit suggests reviewing manual filesystem and canonical paths', () {
    expect(suspiciousPathLines(r"final file = '$root/.sync/users.json';"), [1]);
    expect(suspiciousPathLines("final name = file.path.split('/').last;"), [1]);
    expect(suspiciousPathLines("final wire = canonical.split('/');"), [1]);
  });

  test('native path operations and comments do not need review prompts', () {
    expect(suspiciousPathLines("final name = p.basename(file.path);\n// path.split('/')"), isEmpty);
  });
}
