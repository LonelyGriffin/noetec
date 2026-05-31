// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../../helpers/test_document_factory.dart';
import '../../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // handleKeyEvent — character input (hardware keyboard)
  // ---------------------------------------------------------------------------
  group('handleKeyEvent — character input', () {
    test('inserts a character into the document', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Helloa');
    });

    test('sequential character input builds text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      for (final char in ['a', 'b', 'c']) {
        env.inputService.handleKeyEvent(
          doc.id,
          KeyDownEvent(
            logicalKey: LogicalKeyboardKey.keyA,
            physicalKey: PhysicalKeyboardKey.keyA,
            character: char,
            timeStamp: Duration.zero,
          ),
        );
      }

      expect(blockText(doc, blockId), 'abc');
    });

    test('updates IME state after character input', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.exclamation,
          physicalKey: PhysicalKeyboardKey.digit1,
          character: '!',
          timeStamp: Duration.zero,
        ),
      );

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'Hello!');
      expect(imeState.selection, const TextSelection.collapsed(offset: 6));
    });

    test('advances document cursor after input', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'AB');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 1);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyX,
          physicalKey: PhysicalKeyboardKey.keyX,
          character: 'X',
          timeStamp: Duration.zero,
        ),
      );

      final sel = doc.selection.value as SingleCursorSelectionState;
      final cursor = sel.cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      final flatOffset =
          block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);
      expect(flatOffset, 2);
      expect(blockText(doc, blockId), 'AXB');
    });

    test('does not insert when ctrl is pressed', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Press Ctrl
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Press 'a' while Ctrl is held
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
    });

    test('does not insert when meta is pressed', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Press Meta
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.metaLeft,
          physicalKey: PhysicalKeyboardKey.metaLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Press 'c' while Meta is held
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyC,
          physicalKey: PhysicalKeyboardKey.keyC,
          character: 'c',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
    });

    test('ignores input when no selection exists', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // No click — selection is NoSelectionState
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
    });

    test('inserts into correct segment in multi-segment block', () {
      final (doc, blockId) = createMultiSegmentDocument();
      env.documentsManager.openDocument(doc);

      // Click in bold segment (index 1) at offset 2 ("bo|ld")
      env.inputService.handleTextClick(doc.id, blockId, 1, 2);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyX,
          physicalKey: PhysicalKeyboardKey.keyX,
          character: 'X',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello boXld world');

      // Verify the bold segment got the insertion
      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[1], 'boXld');

      // Verify the segment is still FormattedSegment with bold format
      final block = doc.getBlockById(blockId) as TextBlock;
      final seg = block.segments.value[1];
      expect(seg, isA<FormattedSegment>());
      expect((seg as FormattedSegment).format, TextFormat.bold);
    });

    test('calls onPlatformImeUpdateNeeded after character input', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      var callbackCalled = false;
      env.inputService.onPlatformImeUpdateNeeded = () {
        callbackCalled = true;
      };

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );

      expect(callbackCalled, isTrue);
    });
  });
}
