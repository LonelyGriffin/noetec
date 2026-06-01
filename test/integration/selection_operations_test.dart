// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void pressKey(
    String docId,
    LogicalKeyboardKey logicalKey,
    PhysicalKeyboardKey physicalKey, {
    String? character,
  }) {
    env.inputService.handleKeyEvent(
      docId,
      KeyDownEvent(
        logicalKey: logicalKey,
        physicalKey: physicalKey,
        character: character,
        timeStamp: Duration.zero,
      ),
    );
  }

  void selectRange(String docId, String blockId, int from, int to) {
    env.inputService.handleTextClick(docId, blockId, 0, from);
    env.inputService.handleKeyEvent(
      docId,
      KeyDownEvent(
        logicalKey: LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ),
    );
    env.inputService.handleTextClick(docId, blockId, 0, to);
  }

  // ---------------------------------------------------------------------------
  // Type over selection
  // ---------------------------------------------------------------------------

  group('Type character over selection', () {
    test('typing a character replaces the selected range', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Select "lo W" (3..7).
      selectRange(doc.id, blockId, 3, 7);
      expect(doc.selection.value, isA<RangeSelectionState>());

      // Release shift before typing.
      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Type 'X'.
      pressKey(
        doc.id,
        LogicalKeyboardKey.keyX,
        PhysicalKeyboardKey.keyX,
        character: 'X',
      );

      expect(blockText(doc, blockId), 'HelXorld');
      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset),
        4,
        reason: 'Cursor after inserted "X"',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Backspace with selection
  // ---------------------------------------------------------------------------

  group('Backspace with selection', () {
    test(
      'Backspace deletes selected range without extra character deletion',
      () {
        final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
        env.documentsManager.openDocument(doc);

        selectRange(doc.id, blockId, 2, 8);
        env.inputService.handleKeyUp(
          KeyUpEvent(
            logicalKey: LogicalKeyboardKey.shiftLeft,
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            timeStamp: Duration.zero,
          ),
        );

        pressKey(
          doc.id,
          LogicalKeyboardKey.backspace,
          PhysicalKeyboardKey.backspace,
        );

        expect(blockText(doc, blockId), 'Herld');
        final cursor =
            (doc.selection.value as SingleCursorSelectionState).cursorPos
                as CursorPositionInTextBlock;
        final block = doc.getBlockById(blockId) as TextBlock;
        expect(
          block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset),
          2,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Delete key with selection
  // ---------------------------------------------------------------------------

  group('Delete key with selection', () {
    test('Delete key deletes selected range', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'ABCDEF');
      env.documentsManager.openDocument(doc);

      selectRange(doc.id, blockId, 1, 4);
      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      pressKey(doc.id, LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete);

      expect(blockText(doc, blockId), 'AEF');
    });
  });

  // ---------------------------------------------------------------------------
  // Enter with selection
  // ---------------------------------------------------------------------------

  group('Enter with selection', () {
    test('Enter deletes selection then splits at cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      selectRange(doc.id, blockId, 3, 7);
      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );

      pressKey(doc.id, LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);

      expect(doc.rootBlocks.length, 2);
      expect(blockText(doc, blockId), 'Hel');
      // The new block should contain "orld".
      final newBlockId = (doc.rootBlocks[1] as TextBlock).id;
      expect(blockText(doc, newBlockId), 'orld');
    });
  });

  // ---------------------------------------------------------------------------
  // SelectAll + type replaces everything
  // ---------------------------------------------------------------------------

  group('SelectAll + type', () {
    test('Ctrl+A then type replaces entire document content', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      // Ctrl+A
      pressKey(
        doc.id,
        LogicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlLeft,
      );
      pressKey(doc.id, LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA);

      expect(doc.selection.value, isA<RangeSelectionState>());

      // Release Ctrl.
      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );

      // Type 'Z'.
      pressKey(
        doc.id,
        LogicalKeyboardKey.keyZ,
        PhysicalKeyboardKey.keyZ,
        character: 'Z',
      );

      expect(blockText(doc, blockId), 'Z');
    });
  });
}
