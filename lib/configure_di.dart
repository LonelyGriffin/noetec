// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:uuid/uuid.dart';
import 'package:watch_it/watch_it.dart';

final uuid = Uuid();

void configureDI() {
  GetIt.instance.debugEventsEnabled = true;

  final idService = IdService(() => uuid.v4());
  final openedDocumentsManager = OpenedDocumentsManager();
  final userActionService = UserActionService(openedDocumentsManager, idService);
  final userInputService = UserInputService(
    documentsManager: openedDocumentsManager,
    actionService: userActionService,
  );

  final doc1 = DocumentModel(id: 'doc1');
  for (var i = 0; i < 5; i++) {
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
  di.registerSingleton<UserInputService>(userInputService);
  di.registerSingleton<OpenedDocumentsManager>(openedDocumentsManager);
}
