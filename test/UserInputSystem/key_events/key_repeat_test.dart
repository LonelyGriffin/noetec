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
  // handleKeyRepeat — backspace
  // ---------------------------------------------------------------------------
  group('handleKeyRepeat — backspace', () {
    test('single repeat deletes character before cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 3);

      env.inputService.handleKeyRepeat(
        doc.id,
        KeyRepeatEvent(
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

    test('three repeats delete three characters before cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      for (var i = 0; i < 3; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace,
            timeStamp: Duration.zero,
          ),
        );
      }

      expect(blockText(doc, blockId), 'He');

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'He');
      expect(imeState.selection, const TextSelection.collapsed(offset: 2));
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyRepeat — delete
  // ---------------------------------------------------------------------------
  group('handleKeyRepeat — delete', () {
    test('single repeat deletes character after cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      env.inputService.handleKeyRepeat(
        doc.id,
        KeyRepeatEvent(
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

    test('three repeats delete three characters after cursor', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      for (var i = 0; i < 3; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.delete,
            physicalKey: PhysicalKeyboardKey.delete,
            timeStamp: Duration.zero,
          ),
        );
      }

      expect(blockText(doc, blockId), 'lo');

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.text, 'lo');
      expect(imeState.selection, const TextSelection.collapsed(offset: 0));
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyRepeat — arrow left
  // ---------------------------------------------------------------------------
  group('handleKeyRepeat — arrow left', () {
    test('three repeats move cursor three positions to the left', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      for (var i = 0; i < 3; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.arrowLeft,
            physicalKey: PhysicalKeyboardKey.arrowLeft,
            timeStamp: Duration.zero,
          ),
        );
      }

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 2));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 2);
    });

    test('repeats at beginning of block do not move cursor past offset 0', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 1);

      for (var i = 0; i < 5; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.arrowLeft,
            physicalKey: PhysicalKeyboardKey.arrowLeft,
            timeStamp: Duration.zero,
          ),
        );
      }

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 0));
    });
  });

  // ---------------------------------------------------------------------------
  // handleKeyRepeat — arrow right
  // ---------------------------------------------------------------------------
  group('handleKeyRepeat — arrow right', () {
    test('three repeats move cursor three positions to the right', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 0);

      for (var i = 0; i < 3; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight,
            timeStamp: Duration.zero,
          ),
        );
      }

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 3));

      final cursor = (doc.selection.value as SingleCursorSelectionState)
          .cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 3);
    });

    test('repeats at end of block do not move cursor past last offset', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 4);

      for (var i = 0; i < 5; i++) {
        env.inputService.handleKeyRepeat(
          doc.id,
          KeyRepeatEvent(
            logicalKey: LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight,
            timeStamp: Duration.zero,
          ),
        );
      }

      final imeState = env.inputService.getImeState(doc.id).value;
      expect(imeState.selection, const TextSelection.collapsed(offset: 5));
    });
  });
}
