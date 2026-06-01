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
  // MoveCursor — collapse range selection
  // ---------------------------------------------------------------------------

  group('MoveCursor — collapse range selection', () {
    test('ArrowLeft collapses range to earlier position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      // Create range: anchor=1, extent=4 (selects "ell").
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 1,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 4,
        ),
      );
      expect(doc.selection.value, isA<RangeSelectionState>());

      // ArrowLeft collapses to the earlier position (1).
      actionService.handleAction(
        MoveCursor(documentId: doc.id, direction: CursorMoveDirection.left),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor =
          (sel as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      final flat = block.flatOffsetFromCursor(
        cursor.segmentIndex,
        cursor.offset,
      );
      expect(flat, 1, reason: 'Should collapse to earlier position');
    });

    test('ArrowRight collapses range to later position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 1,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 4,
        ),
      );

      actionService.handleAction(
        MoveCursor(documentId: doc.id, direction: CursorMoveDirection.right),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor =
          (sel as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      final flat = block.flatOffsetFromCursor(
        cursor.segmentIndex,
        cursor.offset,
      );
      expect(flat, 4, reason: 'Should collapse to later position');
    });

    test('ArrowLeft collapses cross-block range to earlier block', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'AB'), ('b2', 'CD')],
      );
      manager.openDocument(doc);

      // Range from b1:1 to b2:1.
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 1,
          extentBlockId: 'b2',
          extentSegmentIndex: 0,
          extentOffset: 1,
        ),
      );

      actionService.handleAction(
        MoveCursor(documentId: doc.id, direction: CursorMoveDirection.left),
      );

      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.blockId, 'b1');
      expect(cursor.offset, 1);
    });

    test('ArrowRight collapses cross-block range to later block', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'AB'), ('b2', 'CD')],
      );
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 1,
          extentBlockId: 'b2',
          extentSegmentIndex: 0,
          extentOffset: 1,
        ),
      );

      actionService.handleAction(
        MoveCursor(documentId: doc.id, direction: CursorMoveDirection.right),
      );

      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.blockId, 'b2');
      expect(cursor.offset, 1);
    });

    test(
      'ArrowLeft collapses reverse range (extent before anchor) correctly',
      () {
        final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
        manager.openDocument(doc);

        // Reverse range: anchor=4, extent=1 (extent is before anchor).
        actionService.handleAction(
          SetRangeSelection(
            documentId: doc.id,
            anchorBlockId: blockId,
            anchorSegmentIndex: 0,
            anchorOffset: 4,
            extentBlockId: blockId,
            extentSegmentIndex: 0,
            extentOffset: 1,
          ),
        );

        actionService.handleAction(
          MoveCursor(documentId: doc.id, direction: CursorMoveDirection.left),
        );

        final cursor =
            (doc.selection.value as SingleCursorSelectionState).cursorPos
                as CursorPositionInTextBlock;
        final block = doc.getBlockById(blockId) as TextBlock;
        final flat = block.flatOffsetFromCursor(
          cursor.segmentIndex,
          cursor.offset,
        );
        expect(
          flat,
          1,
          reason:
              'ArrowLeft should go to earlier position regardless of anchor/extent order',
        );
      },
    );
  });
}
