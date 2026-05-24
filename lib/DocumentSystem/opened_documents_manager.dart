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
