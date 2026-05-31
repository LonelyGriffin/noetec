// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // handleTextClick
  // ---------------------------------------------------------------------------
  group('handleTextClick', () {
    test('sets document selection to the clicked position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor = (sel as SingleCursorSelectionState).cursorPos
          as CursorPositionInTextBlock;
      expect(cursor.blockId, blockId);
      expect(cursor.segmentIndex, 0);
      expect(cursor.offset, 5);
    });

    test('updates IME state to reflect the new cursor position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'Hello World');
      expect(imeState.selection, const TextSelection.collapsed(offset: 5));
    });

    test('second click updates both selection and IME state', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // First click at offset 5
      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Second click at offset 9
      env.inputService.handleTextClick(doc.id, blockId, 0, 9);

      // Document selection should be at 9
      final cursor = (doc.selection.value as SingleCursorSelectionState).cursorPos
          as CursorPositionInTextBlock;
      expect(cursor.offset, 9);

      // IME state should also be at 9
      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 9));
    });
  });

  // ---------------------------------------------------------------------------
  // handleTextDeltas — insertion
  // ---------------------------------------------------------------------------
  group('handleTextDeltas — insertion', () {
    test('inserts text from IME delta into the document', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // Set cursor at offset 5 via click
      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Simulate IME sending an insertion delta at offset 5
      final imeState = env.inputService.getImeState(doc.id).value;
      final delta = TextEditingDeltaInsertion(
        oldText: imeState.text,
        textInserted: '!',
        insertionOffset: 5,
        selection: const TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      );

      env.inputService.handleTextDeltas(doc.id, [delta]);

      expect(blockText(doc, blockId), 'Hello!');
    });

    test('updates IME state after insertion', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      final imeState = env.inputService.getImeState(doc.id).value;
      final delta = TextEditingDeltaInsertion(
        oldText: imeState.text,
        textInserted: '!',
        insertionOffset: 5,
        selection: const TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      );

      env.inputService.handleTextDeltas(doc.id, [delta]);

      final newImeState = env.inputService.getImeState(doc.id).value;
      expect(newImeState.text, 'Hello!');
      expect(newImeState.selection, const TextSelection.collapsed(offset: 6));
    });

    test('updates document selection after insertion', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      final imeState = env.inputService.getImeState(doc.id).value;
      final delta = TextEditingDeltaInsertion(
        oldText: imeState.text,
        textInserted: '!',
        insertionOffset: 5,
        selection: const TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      );

      env.inputService.handleTextDeltas(doc.id, [delta]);

      final sel = doc.selection.value as SingleCursorSelectionState;
      final cursor = sel.cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      final flatOffset = block.flatOffsetFromCursor(
        cursor.segmentIndex, cursor.offset,
      );
      expect(flatOffset, 6);
    });

    test('ignores delta if no selection is set', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // No click — selection is NoSelectionState
      final delta = TextEditingDeltaInsertion(
        oldText: 'Hello',
        textInserted: 'X',
        insertionOffset: 0,
        selection: const TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      );

      env.inputService.handleTextDeltas(doc.id, [delta]);

      // Text should be unchanged
      expect(blockText(doc, blockId), 'Hello');
    });

    test('sequential single-char insertions build up text correctly', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      env.documentsManager.openDocument(doc);

      // Click to set cursor at offset 0
      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      // Type "abc" one char at a time, each time reading IME state for oldText
      for (final char in ['a', 'b', 'c']) {
        final imeState = env.inputService.getImeState(doc.id).value;
        final offset = imeState.selection.baseOffset;
        final delta = TextEditingDeltaInsertion(
          oldText: imeState.text,
          textInserted: char,
          insertionOffset: offset,
          selection: TextSelection.collapsed(offset: offset + 1),
          composing: TextRange.empty,
        );
        env.inputService.handleTextDeltas(doc.id, [delta]);
      }

      expect(blockText(doc, blockId), 'abc');
    });
  });

  // ---------------------------------------------------------------------------
  // Modifier keys
  // ---------------------------------------------------------------------------
  group('modifier keys', () {
    test('tracks ctrl key state', () {
      expect(env.inputService.ctrlPressed, isFalse);

      env.inputService.handleKeyEvent(
        'doc',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.ctrlPressed, isTrue);

      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.ctrlPressed, isFalse);
    });

    test('tracks shift key state', () {
      env.inputService.handleKeyEvent(
        'doc',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.shiftPressed, isTrue);
    });
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

  // ---------------------------------------------------------------------------
  // handleKeyEvent — backspace
  // ---------------------------------------------------------------------------
  group('handleKeyEvent — backspace', () {
    test('deletes character before cursor and updates IME', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Helo');

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'Helo');
      expect(imeState.selection, const TextSelection.collapsed(offset: 2));
    });

    test('does nothing at beginning of block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
    });

    test('sequential backspaces delete multiple characters', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      for (var i = 0; i < 3; i++) {
        env.inputService.handleKeyEvent(
          doc.id,
          KeyDownEvent(
            logicalKey: LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace,
            timeStamp: Duration.zero,
          ),
        );
      }

      expect(blockText(doc, blockId), 'He');
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyEvent — delete
  // ---------------------------------------------------------------------------
  group('handleKeyEvent — delete', () {
    test('deletes character after cursor and updates IME', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.delete,
          physicalKey: PhysicalKeyboardKey.delete,
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Helo');

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'Helo');
      expect(imeState.selection, const TextSelection.collapsed(offset: 2));
    });

    test('does nothing at end of block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.delete,
          physicalKey: PhysicalKeyboardKey.delete,
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyEvent — enter
  // ---------------------------------------------------------------------------
  group('handleKeyEvent — enter', () {
    test('Enter splits block and updates IME to new block', () {
      final (doc, blockId) = createSingleSegmentDocument(
        text: 'Hello World',
      );
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      // Two blocks now
      expect(doc.rootBlocks.length, 2);
      expect(blockText(doc, blockId), 'Hello');
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.computeAllSegmentsText(), ' World');

      // IME state should be for the new block (cursor at start)
      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, ' World');
      expect(imeState.selection, const TextSelection.collapsed(offset: 0));
    });

    test('typing after Enter inserts into new block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Press Enter
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      // Type 'W' in the new block
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyW,
          physicalKey: PhysicalKeyboardKey.keyW,
          character: 'W',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'Hello');
      final newBlock = doc.rootBlocks[1] as TextBlock;
      expect(newBlock.computeAllSegmentsText(), 'W');
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyEvent — arrow keys
  // ---------------------------------------------------------------------------
  group('handleKeyEvent — arrow keys', () {
    test('ArrowLeft moves cursor and updates IME', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      );

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 2));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 2);
    });

    test('ArrowRight moves cursor and updates IME', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 4));
    });

    test('ArrowLeft at beginning does not move', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowLeft,
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      );

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 0));
    });

    test('ArrowRight at end does not move', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 5));
    });

    test('navigate left then type inserts at correct position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Move left twice: cursor goes from 5 → 3
      for (var i = 0; i < 2; i++) {
        env.inputService.handleKeyEvent(
          doc.id,
          KeyDownEvent(
            logicalKey: LogicalKeyboardKey.arrowLeft,
            physicalKey: PhysicalKeyboardKey.arrowLeft,
            timeStamp: Duration.zero,
          ),
        );
      }

      // Type 'X'
      env.inputService.handleKeyEvent(
        doc.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyX,
          physicalKey: PhysicalKeyboardKey.keyX,
          character: 'X',
          timeStamp: Duration.zero,
        ),
      );

      expect(blockText(doc, blockId), 'HelXlo');
    });
  });
}
