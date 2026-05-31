// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

import '../helpers/test_document_factory.dart';

void main() {
  late OpenedDocumentsManager manager;
  late UserActionService actionService;

  setUp(() {
    manager = OpenedDocumentsManager();
    actionService = UserActionService(manager);
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
}
