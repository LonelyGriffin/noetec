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

/// All services wired together for testing, without DI container.
class TestEnvironment {
  final OpenedDocumentsManager documentsManager;
  final IdService idService;
  final UserActionService actionService;
  final UserInputService inputService;

  TestEnvironment({
    required this.documentsManager,
    required this.idService,
    required this.actionService,
    required this.inputService,
  });
}

/// Creates a fully wired [TestEnvironment] with all services connected.
TestEnvironment createTestEnvironment() {
  var idCounter = 0;
  final idService = IdService(() => 'generated-id-${idCounter++}');
  final documentsManager = OpenedDocumentsManager();
  final actionService = UserActionService(documentsManager, idService);
  final inputService = UserInputService(
    documentsManager: documentsManager,
    actionService: actionService,
  );
  return TestEnvironment(
    documentsManager: documentsManager,
    idService: idService,
    actionService: actionService,
    inputService: inputService,
  );
}

/// Creates a [DocumentModel] with a single [TextBlock] containing one plain
/// text segment.
///
/// Returns `(document, blockId)`.
(DocumentModel, String) createSingleSegmentDocument({
  String documentId = 'test-doc',
  String blockId = 'block-1',
  String text = 'Hello, World!',
}) {
  final doc = DocumentModel(id: documentId);
  final block = TextBlock(
    id: blockId,
    documentId: documentId,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: [TextSegment(text: text)]),
  );
  doc.addBlock(block, 0);
  return (doc, blockId);
}

/// Creates a [DocumentModel] with a single [TextBlock] containing multiple
/// segments of different types.
///
/// Default layout:
///   segment 0: "Hello " (plain, length 6)
///   segment 1: "bold"   (bold,  length 4)
///   segment 2: " world" (plain, length 6)
///
/// Total text: "Hello bold world" (length 16)
///
/// Returns `(document, blockId)`.
(DocumentModel, String) createMultiSegmentDocument({
  String documentId = 'test-doc',
  String blockId = 'block-1',
  List<TextSegment>? segments,
}) {
  segments ??= [
    const TextSegment(text: 'Hello '),
    const FormattedSegment(text: 'bold', format: TextFormat.bold),
    const TextSegment(text: ' world'),
  ];

  final doc = DocumentModel(id: documentId);
  final block = TextBlock(
    id: blockId,
    documentId: documentId,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: segments),
  );
  doc.addBlock(block, 0);
  return (doc, blockId);
}

/// Creates a [DocumentModel] with multiple [TextBlock]s.
///
/// Returns `(document, List<blockId>)`.
(DocumentModel, List<String>) createMultiBlockDocument({
  String documentId = 'test-doc',
  List<(String blockId, String text)>? blocks,
}) {
  blocks ??= [
    ('block-1', 'First paragraph'),
    ('block-2', 'Second paragraph'),
    ('block-3', 'Third paragraph'),
  ];

  final doc = DocumentModel(id: documentId);
  final blockIds = <String>[];

  for (var i = 0; i < blocks.length; i++) {
    final (blockId, text) = blocks[i];
    final block = TextBlock(
      id: blockId,
      documentId: documentId,
      parent: ValueNotifier(null),
      segments: ListNotifier(data: [TextSegment(text: text)]),
    );
    doc.addBlock(block, i);
    blockIds.add(blockId);
  }

  return (doc, blockIds);
}

/// Helper to read the full text of a [TextBlock] by its ID from a document.
String blockText(DocumentModel doc, String blockId) {
  final block = doc.getBlockById(blockId) as TextBlock;
  return block.computeAllSegmentsText();
}

/// Helper to read all segment texts of a [TextBlock].
List<String> blockSegmentTexts(DocumentModel doc, String blockId) {
  final block = doc.getBlockById(blockId) as TextBlock;
  return block.segments.value.map((s) => s.text).toList();
}
