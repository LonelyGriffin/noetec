// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:path/path.dart' as p;

/// Resolves a canonical slash-separated document path at a filesystem boundary.
/// The optional context lets tests exercise Windows and POSIX on either host.
String resolveDocumentPath(String root, String documentPath, {p.Context? context}) {
  final paths = context ?? p.context;
  return paths.joinAll([root, ...p.posix.split(documentPath)]);
}

/// Converts a native filesystem path to the canonical document-path namespace.
String relativeDocumentPath(String path, {required String from, p.Context? context}) {
  final paths = context ?? p.context;
  return p.posix.joinAll(paths.split(paths.relative(path, from: from)));
}
