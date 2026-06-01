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

  group('SelectWord', () {
    test('selects word in middle of text', () {
      // "Hello World" -- offset 2 is inside "Hello"
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;

      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      final block = doc.getBlockById(blockId) as TextBlock;
      final anchorFlat = block.flatOffsetFromCursor(
        anchor.segmentIndex,
        anchor.offset,
      );
      final extentFlat = block.flatOffsetFromCursor(
        extent.segmentIndex,
        extent.offset,
      );

      expect(anchorFlat, 0, reason: '"Hello" starts at 0');
      expect(extentFlat, 5, reason: '"Hello" ends at 5');
    });

    test('selects word at end of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 8,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(anchor.segmentIndex, anchor.offset), 6);
      expect(
        block.flatOffsetFromCursor(extent.segmentIndex, extent.offset),
        11,
      );
    });

    test('selects single space character', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 5,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(anchor.segmentIndex, anchor.offset), 5);
      expect(block.flatOffsetFromCursor(extent.segmentIndex, extent.offset), 6);
    });

    test('selects word across segments', () {
      // "Hello " + bold "bold" + " world" = "Hello bold world"
      // offset in segment 1 (bold), char 1 ('o') -> word "bold" at flat 6..10
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 1,
          offset: 1,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(anchor.segmentIndex, anchor.offset), 6);
      expect(
        block.flatOffsetFromCursor(extent.segmentIndex, extent.offset),
        10,
      );
    });

    test('collapses to cursor on empty block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 0,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
    });

    test('selects punctuation as single character', () {
      // "Hello, World!" -- offset 5 is comma
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello, World!');
      manager.openDocument(doc);

      actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 5,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(anchor.segmentIndex, anchor.offset), 5);
      expect(block.flatOffsetFromCursor(extent.segmentIndex, extent.offset), 6);
    });
  });
}
