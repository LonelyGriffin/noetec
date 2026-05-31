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
