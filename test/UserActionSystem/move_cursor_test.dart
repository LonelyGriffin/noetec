// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

import '../helpers/test_document_factory.dart';

void main() {
  late OpenedDocumentsManager manager;
  late IdService idService;
  late UserActionService actionService;

  setUp(() {
    var idCounter = 0;
    idService = IdService(() => 'generated-id-${idCounter++}');
    manager = OpenedDocumentsManager();
    actionService = UserActionService(manager, idService);
  });

  // ---------------------------------------------------------------------------
  // MoveCursor
  // ---------------------------------------------------------------------------
  group('MoveCursor', () {
    test('left from middle moves cursor by -1', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      // Set cursor at offset 3
      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 3,
      ));

      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.left,
      ));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 2);
    });

    test('left from beginning stays at 0', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 0,
      ));

      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.left,
      ));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 0);
    });

    test('right from middle moves cursor by +1', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 3,
      ));

      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.right,
      ));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 4);
    });

    test('right from end stays at end', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 5,
      ));

      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.right,
      ));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 5);
    });

    test('left/right navigates across segment boundaries', () {
      // "Hello " (6) + "bold" (4) + " world" (6)
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Click at segment 0, offset 6 (end of "Hello " = boundary with "bold")
      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 6,
      ));

      // Move right — should go to flat offset 7
      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.right,
      ));

      var cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 7);

      // Move left — should go back to flat offset 6
      actionService.handleAction(MoveCursor(
        documentId: doc.id,
        direction: CursorMoveDirection.left,
      ));

      cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 6);
    });
  });
}
