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
  // DeleteSelection — single block
  // ---------------------------------------------------------------------------

  group('DeleteSelection — single block', () {
    test('deletes selected range in the middle of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      // Select "lo Wo" (offset 3..8).
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 3,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 8,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), 'Helrld');
      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 3);
    });

    test('deletes from start of block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 0,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 3,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), 'lo');
      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 0);
    });

    test('deletes entire block content leaving empty segment', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 0,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 5,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), '');
      expect(doc.rootBlocks.length, 1, reason: 'Block itself should remain');
    });

    test('deletes across formatted segments preserving formatting', () {
      final (doc, blockId) = createMultiSegmentDocument();
      // "Hello bold world" — seg0:"Hello " seg1:"bold" seg2:" world"
      manager.openDocument(doc);

      // Select "lo bold w" (offset 3..13).
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 3,
          extentBlockId: blockId,
          extentSegmentIndex: 2,
          extentOffset:
              2, // 2 chars into " world" = " w" → after deletion keep "orld"
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), 'Helorld');
      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 3);
    });

    test('handles reverse range (extent before anchor)', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      // Reverse range: anchor=8, extent=3.
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 8,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 3,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), 'Helrld');
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteSelection — multi-block
  // ---------------------------------------------------------------------------

  group('DeleteSelection — multi-block', () {
    test('deletes selection spanning two blocks', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First paragraph'), ('b2', 'Second paragraph')],
      );
      manager.openDocument(doc);

      // Select from b1 offset 5 to b2 offset 7: " paragraph" + "Second " → delete.
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 5,
          extentBlockId: 'b2',
          extentSegmentIndex: 0,
          extentOffset: 7,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(doc.rootBlocks.length, 1, reason: 'Two blocks merged into one');
      expect(blockText(doc, 'b1'), 'Firstparagraph');

      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.blockId, 'b1');
      final block = doc.getBlockById('b1') as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 5);
    });

    test('deletes selection spanning three blocks, removing middle block', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Middle'), ('b3', 'Third')],
      );
      manager.openDocument(doc);

      // Select from b1:2 to b3:3.
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 2,
          extentBlockId: 'b3',
          extentSegmentIndex: 0,
          extentOffset: 3,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(doc.rootBlocks.length, 1, reason: 'Three blocks merged into one');
      expect(blockText(doc, 'b1'), 'Fird');

      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.blockId, 'b1');
    });

    test('deletes entire content with SelectAll + DeleteSelection', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second'), ('b3', 'Third')],
      );
      manager.openDocument(doc);

      actionService.handleAction(SelectAll(documentId: doc.id));
      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(doc.rootBlocks.length, 1);
      expect(blockText(doc, 'b1'), '');
    });

    test('handles reverse cross-block range', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'AAAA'), ('b2', 'BBBB')],
      );
      manager.openDocument(doc);

      // Reverse: anchor in b2, extent in b1.
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b2',
          anchorSegmentIndex: 0,
          anchorOffset: 2,
          extentBlockId: 'b1',
          extentSegmentIndex: 0,
          extentOffset: 1,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(doc.rootBlocks.length, 1);
      expect(blockText(doc, 'b1'), 'ABB');
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteSelection does nothing on collapsed selection
  // ---------------------------------------------------------------------------

  group('DeleteSelection — no-op', () {
    test('does nothing when selection is collapsed', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      actionService.handleAction(DeleteSelection(documentId: doc.id));

      expect(blockText(doc, blockId), 'Hello', reason: 'Text unchanged');
      expect(doc.selection.value, isA<SingleCursorSelectionState>());
    });
  });
}
