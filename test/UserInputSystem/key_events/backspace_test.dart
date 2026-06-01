// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_document_factory.dart';
import '../../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
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
}
