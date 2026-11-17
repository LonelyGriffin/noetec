// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/document_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final style in [p.Style.windows, p.Style.posix]) {
    final paths = p.Context(style: style);
    final root = style == p.Style.windows ? r'C:\vault with spaces' : '/vault with spaces';
    group('$style document paths', () {
      test('canonical nested document resolves to a native path and back', () {
        const document = 'pages/notes/идея.md';
        final native = resolveDocumentPath(root, document, context: paths);
        expect(native, paths.join(root, 'pages', 'notes', 'идея.md'));
        expect(relativeDocumentPath(native, from: root, context: paths), document);
      });

      test('WAL and oplog directory round trips retain canonical paths', () {
        for (final base in [paths.join(root, '.noetec', 'wal'), paths.join(root, '.sync')]) {
          final native = resolveDocumentPath(base, 'pages/nested/note.md', context: paths);
          expect(relativeDocumentPath(native, from: base, context: paths), 'pages/nested/note.md');
        }
      });
    });
  }
}
