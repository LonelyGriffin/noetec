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
  // DeleteTextForward
  // ---------------------------------------------------------------------------
  group('DeleteTextForward', () {
    test('deletes character after cursor in middle of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextForward(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 2,
      ));

      expect(blockText(doc, blockId), 'Helo');
    });

    test('does nothing when cursor is at end of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextForward(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 5,
      ));

      expect(blockText(doc, blockId), 'Hello');
    });

    test('deletes first character', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextForward(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 0,
      ));

      expect(blockText(doc, blockId), 'ello');
    });

    test('cursor stays at same flat offset', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextForward(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 2,
      ));

      final sel = doc.selection.value as SingleCursorSelectionState;
      final cursor = sel.cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 2);
    });

    test('deletes from correct segment in multi-segment block', () {
      // "Hello " (6) + "bold" (4) + " world" (6) = 16
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Delete at flat offset 6 → deletes 'b' from bold segment
      actionService.handleAction(DeleteTextForward(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 6,
      ));

      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[0], 'Hello ');
      expect(segTexts[1], 'old');
      expect(segTexts[2], ' world');
    });
  });
}
