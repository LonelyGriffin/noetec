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
  // ExtendSelection — single block
  // ---------------------------------------------------------------------------

  group('ExtendSelection — from collapsed cursor', () {
    test('extends right from middle of block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      // Place cursor at offset 2 ("He|llo").
      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      // Extend selection right.
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;

      final anchor = range.anchor as CursorPositionInTextBlock;
      expect(anchor.blockId, blockId);
      expect(anchor.segmentIndex, 0);
      expect(anchor.offset, 2);

      final extent = range.extent as CursorPositionInTextBlock;
      expect(extent.blockId, blockId);
      expect(extent.segmentIndex, 0);
      expect(extent.offset, 3);
    });

    test('extends left from middle of block', () {
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

      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.left,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;

      final anchor = range.anchor as CursorPositionInTextBlock;
      expect(anchor.offset, 2);

      final extent = range.extent as CursorPositionInTextBlock;
      expect(extent.offset, 1);
    });

    test('does nothing when extending left at start of first block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 0,
        ),
      );

      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.left,
        ),
      );

      // Should remain collapsed cursor.
      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
    });

    test('does nothing when extending right at end of last block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 5,
        ),
      );

      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
    });
  });

  // ---------------------------------------------------------------------------
  // ExtendSelection — expanding existing range
  // ---------------------------------------------------------------------------

  group('ExtendSelection — from existing range', () {
    test('extends an existing range further right', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 1,
        ),
      );

      // Extend right twice: H|e -> H|el -> H|ell
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.offset, 1, reason: 'Anchor stays at original position');
      expect(extent.offset, 3, reason: 'Extent moved two positions right');
    });

    test('collapses range when extent returns to anchor', () {
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

      // Extend right: anchor=2, extent=3
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );
      expect(doc.selection.value, isA<RangeSelectionState>());

      // Extend left: anchor=2, extent=2 → collapses
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.left,
        ),
      );
      expect(doc.selection.value, isA<SingleCursorSelectionState>());

      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.offset, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // ExtendSelection — cross-block
  // ---------------------------------------------------------------------------

  group('ExtendSelection — cross-block', () {
    test('extends right across block boundary', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'AB'), ('b2', 'CD')],
      );
      manager.openDocument(doc);

      // Place cursor at end of block 1 (offset 2).
      final block1 = doc.getBlockById('b1') as TextBlock;
      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: 'b1',
          segmentIndex: 0,
          offset: block1.computeAllSegmentsText().length,
        ),
      );

      // Extend right → should cross to start of block 2.
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.right,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.blockId, 'b1');
      expect(extent.blockId, 'b2');
      expect(extent.offset, 0);
    });

    test('extends left across block boundary', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'AB'), ('b2', 'CD')],
      );
      manager.openDocument(doc);

      // Place cursor at start of block 2 (offset 0).
      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: 'b2',
          segmentIndex: 0,
          offset: 0,
        ),
      );

      // Extend left → should cross to end of block 1.
      actionService.handleAction(
        ExtendSelection(
          documentId: doc.id,
          direction: CursorMoveDirection.left,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.blockId, 'b2');
      expect(extent.blockId, 'b1');
      expect(extent.offset, 2, reason: 'Extent should be at end of "AB"');
    });
  });
}
