// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Shift+Arrow — extend selection
  // ---------------------------------------------------------------------------

  group('Shift+Arrow — extend selection', () {
    test('Shift+Right creates range selection from collapsed cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // Place cursor at offset 2.
      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      // Press Shift down.
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Press ArrowRight (with Shift held).
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.offset, 2);
      expect(extent.offset, 3);
    });

    test('Shift+Left creates range selection from collapsed cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.offset, 3);
      expect(extent.offset, 2);
    });

    test('Arrow without Shift after Shift+Arrow collapses selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      // Shift+Right → range.
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );
      expect(doc.selection.value, isA<RangeSelectionState>());

      // Release Shift.
      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      // ArrowRight without Shift → should collapse to extent position.
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
    });
  });

  // ---------------------------------------------------------------------------
  // Shift+Click
  // ---------------------------------------------------------------------------

  group('Shift+Click', () {
    test('Shift+Click extends from cursor to click position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Place cursor at offset 2.
      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      // Hold Shift.
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Click at offset 8 with Shift held.
      env.inputService.handleTextClick(doc.id, blockId, 0, 8);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(
        anchor.offset,
        2,
        reason: 'Anchor should be original cursor position',
      );
      expect(extent.offset, 8, reason: 'Extent should be click position');
    });

    test('Shift+Click updates extent of existing range selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      // Hold Shift.
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Shift+Click at 8.
      env.inputService.handleTextClick(doc.id, blockId, 0, 8);
      // Shift+Click again at 5 — should update extent, keep anchor.
      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.offset, 2, reason: 'Anchor stays at original position');
      expect(extent.offset, 5, reason: 'Extent updated to new click position');
    });
  });

  // ---------------------------------------------------------------------------
  // Ctrl+A / Cmd+A — Select All
  // ---------------------------------------------------------------------------

  group('Ctrl+A — Select All', () {
    test('Ctrl+A selects all text in single block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      // Ctrl+A
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.blockId, blockId);
      expect(anchor.offset, 0);
      expect(extent.blockId, blockId);
      expect(extent.offset, 5);
    });

    test('Meta+A (Cmd+A on Mac) also selects all', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      // Meta+A
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.metaLeft,
          physicalKey: PhysicalKeyboardKey.metaLeft,
          timeStamp: Duration.zero,
        ),
      );
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );

      expect(doc.selection.value, isA<RangeSelectionState>());
    });
  });

  // ---------------------------------------------------------------------------
  // Drag selection
  // ---------------------------------------------------------------------------

  group('Drag selection', () {
    test('drag start + update creates range selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      env.inputService.handleDragStart(doc.id, blockId, 0, 2);
      expect(
        doc.selection.value,
        isA<SingleCursorSelectionState>(),
        reason: 'Drag start sets collapsed cursor',
      );

      env.inputService.handleDragUpdate(doc.id, blockId, 0, 7);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.offset, 2);
      expect(extent.offset, 7);
    });

    test('drag across blocks creates cross-block range selection', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second')],
      );
      env.documentsManager.openDocument(doc);

      env.inputService.handleDragStart(doc.id, 'b1', 0, 2);
      env.inputService.handleDragUpdate(doc.id, 'b2', 0, 3);

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;
      expect(anchor.blockId, 'b1');
      expect(anchor.offset, 2);
      expect(extent.blockId, 'b2');
      expect(extent.offset, 3);
    });

    test('drag end triggers IME sync callback', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      var callbackCalled = false;
      env.inputService.onPlatformImeUpdateNeeded = () {
        callbackCalled = true;
      };

      env.inputService.handleDragStart(doc.id, blockId, 0, 1);
      env.inputService.handleDragUpdate(doc.id, blockId, 0, 4);
      env.inputService.handleDragEnd(doc.id);

      expect(callbackCalled, isTrue);
    });
  });
}
