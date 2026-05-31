// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_model.dart';

class OpenedDocumentsManager {
  final MapNotifier<String, DocumentModel> openedDocuments = MapNotifier(
    data: {},
  );

  void openDocument(DocumentModel document) {
    openedDocuments[document.id] = document;
  }

  DocumentModel? getDocument(String id) {
    return openedDocuments[id];
  }
}
