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
  // ClickOnTextBlock
  // ---------------------------------------------------------------------------
  group('ClickOnTextBlock', () {
    test('sets selection to the clicked position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 3,
      ));

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor = (sel as SingleCursorSelectionState).cursorPos as CursorPositionInTextBlock;
      expect(cursor.blockId, blockId);
      expect(cursor.segmentIndex, 0);
      expect(cursor.offset, 3);
    });

    test('click on different block updates selection to new block', () {
      final (doc, blockIds) = createMultiBlockDocument();
      manager.openDocument(doc);

      // Click on first block
      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockIds[0],
        segmentIndex: 0,
        offset: 2,
      ));

      var cursor = (doc.selection.value as SingleCursorSelectionState).cursorPos
          as CursorPositionInTextBlock;
      expect(cursor.blockId, blockIds[0]);

      // Click on second block
      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockIds[1],
        segmentIndex: 0,
        offset: 5,
      ));

      cursor = (doc.selection.value as SingleCursorSelectionState).cursorPos
          as CursorPositionInTextBlock;
      expect(cursor.blockId, blockIds[1]);
      expect(cursor.offset, 5);
    });

    test('click then insert places text at click position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      // Click at offset 5 ("Hello|")
      actionService.handleAction(ClickOnTextBlock(
        documentId: doc.id,
        blockId: blockId,
        segmentIndex: 0,
        offset: 5,
      ));

      // Insert text at the cursor position (flatOffset from selection)
      final cursor = (doc.selection.value as SingleCursorSelectionState).cursorPos
          as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      final flatOffset = block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: flatOffset,
        text: ',',
      ));

      expect(blockText(doc, blockId), 'Hello, World');
    });
  });
}
