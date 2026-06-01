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
  // SplitTextBlock
  // ---------------------------------------------------------------------------
  group('SplitTextBlock', () {
    test('splits block in the middle — two blocks with correct text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 5,
      ));

      expect(doc.rootBlocks.length, 2);
      expect(blockText(doc, blockId), 'Hello');
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.computeAllSegmentsText(), ' World');
    });

    test('split at beginning — first block empty, second has full text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 0,
      ));

      expect(doc.rootBlocks.length, 2);
      expect(blockText(doc, blockId), '');
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.computeAllSegmentsText(), 'Hello');
    });

    test('split at end — first has full text, second block empty', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 5,
      ));

      expect(doc.rootBlocks.length, 2);
      expect(blockText(doc, blockId), 'Hello');
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.computeAllSegmentsText(), '');
    });

    test('cursor moves to beginning of new block after split', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 5,
      ));

      final sel = doc.selection.value as SingleCursorSelectionState;
      final cursor = sel.cursorPos as CursorPositionInTextBlock;
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(cursor.blockId, newBlock.id);
      expect(cursor.segmentIndex, 0);
      expect(cursor.offset, 0);
    });

    test('new block is inserted right after original', () {
      final (doc, _) = createMultiBlockDocument(
        blocks: [
          ('b1', 'First'),
          ('b2', 'Second'),
          ('b3', 'Third'),
        ],
      );
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: 'b2',
        splitFlatOffset: 3,
      ));

      expect(doc.rootBlocks.length, 4);
      expect((doc.rootBlocks[0] as TextBlock).id, 'b1');
      expect((doc.rootBlocks[1] as TextBlock).id, 'b2');
      // new block at index 2
      expect((doc.rootBlocks[2] as TextBlock).computeAllSegmentsText(), 'ond');
      expect((doc.rootBlocks[3] as TextBlock).id, 'b3');
    });

    test('split preserves segment types in multi-segment block', () {
      // "Hello " (6) + "bold" (4) + " world" (6) = 16
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Split at flat offset 8 = "Hello " (6) + 2 into "bold"
      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 8,
      ));

      expect(doc.rootBlocks.length, 2);

      // First block: "Hello " (plain) + "bo" (bold)
      final block1 = doc.rootBlocks[0] as TextBlock;
      expect(block1.computeAllSegmentsText(), 'Hello bo');
      expect(block1.segments.value[0].text, 'Hello ');
      final seg1bold = block1.segments.value[1];
      expect(seg1bold, isA<FormattedSegment>());
      expect((seg1bold as FormattedSegment).format, TextFormat.bold);
      expect(seg1bold.text, 'bo');

      // Second block: "ld" (bold) + " world" (plain)
      final block2 = doc.rootBlocks[1] as TextBlock;
      expect(block2.computeAllSegmentsText(), 'ld world');
      final seg2bold = block2.segments.value[0];
      expect(seg2bold, isA<FormattedSegment>());
      expect((seg2bold as FormattedSegment).format, TextFormat.bold);
      expect(seg2bold.text, 'ld');
      expect(block2.segments.value[1].text, ' world');
    });

    test('split at segment boundary', () {
      // "Hello " (6) + "bold" (4) + " world" (6)
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Split at flat offset 6 = end of "Hello " segment
      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 6,
      ));

      expect(doc.rootBlocks.length, 2);
      final block1 = doc.rootBlocks[0] as TextBlock;
      expect(block1.computeAllSegmentsText(), 'Hello ');
      final block2 = doc.rootBlocks[1] as TextBlock;
      expect(block2.computeAllSegmentsText(), 'bold world');
    });

    test('rootBlocks.length increases by 1', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      expect(doc.rootBlocks.length, 1);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 3,
      ));

      expect(doc.rootBlocks.length, 2);
    });

    test('new block gets ID from IdService', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(SplitTextBlock(
        documentId: doc.id,
        blockId: blockId,
        splitFlatOffset: 3,
      ));

      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.id, 'generated-id-0');
    });
  });
}
