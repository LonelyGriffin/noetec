// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> expectSessionJsonExists(String vaultPath) async {
  final sessionFile = File(p.join(vaultPath, '.noetec', 'session.json'));
  expect(
    await sessionFile.exists(),
    isTrue,
    reason: 'session.json should exist at $vaultPath/.noetec/session.json',
  );
}

Future<void> expectSessionJsonValid(
  String vaultPath, {
  List<String> expectedOpenPagePaths = const [],
  String? expectedActivePagePath,
}) async {
  final sessionFile = File(p.join(vaultPath, '.noetec', 'session.json'));
  expect(
    await sessionFile.exists(),
    isTrue,
    reason: 'session.json should exist at $vaultPath/.noetec/session.json',
  );

  final raw = await sessionFile.readAsString();
  final content = jsonDecode(raw) as Map<String, dynamic>;
  final openPages = (content['open_pages'] as List).cast<String>();
  final activePage = content['active_page'] as String?;

  expect(
    openPages,
    hasLength(expectedOpenPagePaths.length),
    reason: 'open_pages count should match',
  );
  expect(
    openPages,
    containsAll(expectedOpenPagePaths),
    reason: 'open_pages should contain expected entries',
  );

  if (expectedActivePagePath != null) {
    expect(
      activePage,
      equals(expectedActivePagePath),
      reason: 'active_page should be "$expectedActivePagePath"',
    );
  } else {
    expect(activePage, isNull, reason: 'active_page should be null');
  }
}
