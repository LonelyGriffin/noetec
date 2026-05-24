
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/LayoutSystem/opened_document_layouts_system.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';
import 'package:uuid/uuid.dart';
import 'package:watch_it/watch_it.dart';

final uuid = Uuid();

void configureDI() {
  GetIt.instance.debugEventsEnabled = true;

  final openedDocumentsManager = OpenedDocumentsManager();
  final userActionService = UserActionService(openedDocumentsManager);
  final userRawTextInputService = UserRawTextInputService(
    documentsManager: openedDocumentsManager,
    actionService: userActionService,
  );
  final openedDocumentLayoutsSystem = OpenedDocumentLayoutsSystem();

  final doc1 = DocumentModel(id: 'doc1');
  for (var i = 0; i < 10000; i++) {
    final paragraph = TextBlock(
      id: uuid.v4(),
      documentId: doc1.id,
      parent: ValueNotifier(null),
      segments: ListNotifier(
        data: [
          TextSegment(text: 'Paragraph $i: Hello, World! '),
          FormattedSegment(text: 'Bold Text $i', format: TextFormat.bold),
          TextSegment(text: ' - '),
          LinkSegment(text: 'Link $i', url: 'https://example.com/$i'),
          TextSegment(text: ' - '),
          FormattedSegment(text: 'Italic $i', format: TextFormat.italic),
          TextSegment(text: ' - End of paragraph $i'),
        ],
      ),
    );
    doc1.addBlock(paragraph, i);
  }
  openedDocumentsManager.openDocument(doc1);

  di.registerSingleton<UserActionService>(userActionService);
  di.registerSingleton<UserRawTextInputService>(userRawTextInputService);
  di.registerSingleton<OpenedDocumentsManager>(openedDocumentsManager);
  di.registerSingleton<OpenedDocumentLayoutsSystem>(
    openedDocumentLayoutsSystem,
  );
}
