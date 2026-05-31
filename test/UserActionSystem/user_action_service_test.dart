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
  // InsertText
  // ---------------------------------------------------------------------------
  group('InsertText', () {
    test('inserts text at the beginning of a single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 0,
        text: 'X',
      ));

      expect(blockText(doc, blockId), 'XHello');
    });

    test('inserts text in the middle of a single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 2,
        text: 'XX',
      ));

      expect(blockText(doc, blockId), 'HeXXllo');
    });

    test('inserts text at the end of a single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 5,
        text: '!',
      ));

      expect(blockText(doc, blockId), 'Hello!');
    });

    test('inserts multi-char text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'ab');
      manager.openDocument(doc);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 1,
        text: 'XYZ',
      ));

      expect(blockText(doc, blockId), 'aXYZb');
    });

    test('updates selection to cursor after inserted text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 2,
        text: 'XX',
      ));

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor = (sel as SingleCursorSelectionState).cursorPos;
      expect(cursor, isA<CursorPositionInTextBlock>());
      final textCursor = cursor as CursorPositionInTextBlock;
      expect(textCursor.blockId, blockId);
      // New flat offset = 2 + 2 = 4
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(textCursor.segmentIndex, textCursor.offset), 4);
    });

    test('inserts into correct segment in multi-segment block', () {
      // "Hello " (6) + "bold" (4) + " world" (6)
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Insert at flat offset 8 = "Hello " + 2 chars into "bold"
      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 8,
        text: 'X',
      ));

      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[0], 'Hello ');
      expect(segTexts[1], 'boXld');
      expect(segTexts[2], ' world');
      expect(blockText(doc, blockId), 'Hello boXld world');
    });

    test('preserves segment types on insert', () {
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Insert into the bold segment (index 1)
      actionService.handleAction(InsertText(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 7, // "Hello " (6) + 1 into "bold"
        text: 'Z',
      ));

      final block = doc.getBlockById(blockId) as TextBlock;
      final seg1 = block.segments.value[1];
      expect(seg1, isA<FormattedSegment>());
      expect((seg1 as FormattedSegment).format, TextFormat.bold);
      expect(seg1.text, 'bZold');
    });

    test('sequential inserts at advancing offsets produce correct text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      manager.openDocument(doc);

      // Type "abc" one character at a time
      actionService.handleAction(InsertText(
        documentId: doc.id, blockId: blockId, flatOffset: 0, text: 'a',
      ));
      actionService.handleAction(InsertText(
        documentId: doc.id, blockId: blockId, flatOffset: 1, text: 'b',
      ));
      actionService.handleAction(InsertText(
        documentId: doc.id, blockId: blockId, flatOffset: 2, text: 'c',
      ));

      expect(blockText(doc, blockId), 'abc');
    });
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

  // ---------------------------------------------------------------------------
  // splitSegmentsAt
  // ---------------------------------------------------------------------------
  group('splitSegmentsAt', () {
    test('split at start produces empty before, full after', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = actionService.splitSegmentsAt(segments, 0);
      expect(before, isEmpty);
      expect(after.length, 2);
      expect(after[0].text, 'Hello');
      expect(after[1].text, ' World');
    });

    test('split at end produces full before, empty after', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = actionService.splitSegmentsAt(segments, 11);
      expect(before.length, 2);
      expect(after, isEmpty);
    });

    test('split at segment boundary', () {
      final segments = [
        const TextSegment(text: 'Hello'),
        const TextSegment(text: ' World'),
      ];

      final (before, after) = actionService.splitSegmentsAt(segments, 5);
      expect(before.length, 1);
      expect(before[0].text, 'Hello');
      expect(after.length, 1);
      expect(after[0].text, ' World');
    });

    test('split in middle of segment', () {
      final segments = [
        const TextSegment(text: 'Hello World'),
      ];

      final (before, after) = actionService.splitSegmentsAt(segments, 5);
      expect(before.length, 1);
      expect(before[0].text, 'Hello');
      expect(after.length, 1);
      expect(after[0].text, ' World');
    });

    test('split preserves FormattedSegment type', () {
      final segments = [
        const FormattedSegment(text: 'BoldText', format: TextFormat.bold),
      ];

      final (before, after) = actionService.splitSegmentsAt(segments, 4);
      expect(before[0], isA<FormattedSegment>());
      expect((before[0] as FormattedSegment).format, TextFormat.bold);
      expect(before[0].text, 'Bold');
      expect(after[0], isA<FormattedSegment>());
      expect((after[0] as FormattedSegment).format, TextFormat.bold);
      expect(after[0].text, 'Text');
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteTextBack
  // ---------------------------------------------------------------------------
  group('DeleteTextBack', () {
    test('deletes character before cursor in middle of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 3,
      ));

      expect(blockText(doc, blockId), 'Helo');
    });

    test('does nothing when flatOffset is 0', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 0,
      ));

      expect(blockText(doc, blockId), 'Hello');
    });

    test('deletes last character', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 5,
      ));

      expect(blockText(doc, blockId), 'Hell');
    });

    test('moves cursor back by one', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 3,
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

      // Delete at flat offset 8 = "Hello " (6) + 2 into "bold" → deletes 'o'
      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 8,
      ));

      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[0], 'Hello ');
      expect(segTexts[1], 'bld');
      expect(segTexts[2], ' world');
    });

    test('preserves segment type on delete', () {
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Delete inside bold segment
      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 8,
      ));

      final block = doc.getBlockById(blockId) as TextBlock;
      final seg1 = block.segments.value[1];
      expect(seg1, isA<FormattedSegment>());
      expect((seg1 as FormattedSegment).format, TextFormat.bold);
    });
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
