// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Touch tap — places cursor
  // ---------------------------------------------------------------------------

  group('Touch tap places cursor', () {
    test('tap on text sets cursor at tapped position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Simulate touch tap: handleTextClick (same as tap callback uses).
      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor =
          (sel as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.blockId, blockId);
      expect(cursor.offset, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // Long press — select word
  // ---------------------------------------------------------------------------

  group('Touch long press selects word', () {
    test('long press on a word selects the whole word', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // SelectWord action (dispatched by long press handler in the widget).
      env.actionService.handleAction(
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
      expect(
        block.flatOffsetFromCursor(anchor.segmentIndex, anchor.offset),
        0,
        reason: '"Hello" starts at 0',
      );
      expect(
        block.flatOffsetFromCursor(extent.segmentIndex, extent.offset),
        5,
        reason: '"Hello" ends at 5',
      );
    });

    test('long press on space selects the space', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      env.actionService.handleAction(
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

  // ---------------------------------------------------------------------------
  // Long press on cursor — drag cursor
  // ---------------------------------------------------------------------------

  group('Touch long press on cursor starts drag', () {
    test('long press on extent position then drag updates selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Create a range selection: "Hello" (0..5).
      env.actionService.handleAction(
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

      // Simulate drag update (user drags extent from 5 to 8).
      env.inputService.handleDragUpdate(doc.id, blockId, 0, 8);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.offset, 0, reason: 'anchor stays at 0');
      expect(extent.offset, 8, reason: 'extent moved to 8');
    });

    test('long press on anchor swaps then drag updates extent', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Create a range selection: anchor=0, extent=5.
      env.actionService.handleAction(
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

      // User long-pressed on anchor (offset 0) — widget calls swap.
      env.inputService.swapSelectionAnchors(doc.id);

      // After swap: anchor=5, extent=0.
      final afterSwap = doc.selection.value as RangeSelectionState;
      expect((afterSwap.anchor as CursorPositionInTextBlock).offset, 5);
      expect((afterSwap.extent as CursorPositionInTextBlock).offset, 0);

      // Now drag extent from 0 to 3.
      env.inputService.handleDragUpdate(doc.id, blockId, 0, 3);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.offset, 5, reason: 'anchor (formerly extent) stays at 5');
      expect(extent.offset, 3, reason: 'extent moved to 3');
    });
  });

  // ---------------------------------------------------------------------------
  // Select word → copy
  // ---------------------------------------------------------------------------

  group('Touch select word then copy', () {
    test('select word and copy produces markdown in clipboard', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Select "Hello".
      env.actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      // Extract markdown (this is what handleCopy does internally before
      // writing to clipboard).
      final markdown = env.actionService.extractSelectedMarkdown(doc.id);
      expect(markdown, isNotNull);
      expect(markdown, contains('Hello'));
    });
  });

  // ---------------------------------------------------------------------------
  // Select word → cut → paste
  // ---------------------------------------------------------------------------

  group('Touch select word then cut then paste', () {
    test('cut removes selected word, paste restores it', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Select "Hello".
      env.actionService.handleAction(
        SelectWord(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      // Extract for clipboard.
      final markdown = env.actionService.extractSelectedMarkdown(doc.id)!;

      // Delete selection (cut).
      env.actionService.handleAction(DeleteSelection(documentId: doc.id));
      expect(blockText(doc, blockId), ' World');

      // Paste.
      env.actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: markdown),
      );
      expect(blockText(doc, blockId), 'Hello World');
    });
  });

  // ---------------------------------------------------------------------------
  // Select All via action
  // ---------------------------------------------------------------------------

  group('Touch select all then copy', () {
    test('select all then extract markdown includes entire document', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second')],
      );
      env.documentsManager.openDocument(doc);

      env.actionService.handleAction(SelectAll(documentId: doc.id));

      final markdown = env.actionService.extractSelectedMarkdown(doc.id);
      expect(markdown, isNotNull);
      expect(markdown, contains('First'));
      expect(markdown, contains('Second'));
    });
  });

  // ---------------------------------------------------------------------------
  // Input mode switching
  // ---------------------------------------------------------------------------

  group('Input mode switching', () {
    test('service methods work identically regardless of input mode', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Simulate "touch tap" (just handleTextClick, same API).
      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      final sel1 = doc.selection.value;
      expect(sel1, isA<SingleCursorSelectionState>());
      expect(
        ((sel1 as SingleCursorSelectionState).cursorPos
                as CursorPositionInTextBlock)
            .offset,
        3,
      );

      // Simulate "mouse click" (same API, different call site).
      env.inputService.handleTextClick(doc.id, blockId, 0, 7);

      final sel2 = doc.selection.value;
      expect(sel2, isA<SingleCursorSelectionState>());
      expect(
        ((sel2 as SingleCursorSelectionState).cursorPos
                as CursorPositionInTextBlock)
            .offset,
        7,
      );
    });
  });
}
