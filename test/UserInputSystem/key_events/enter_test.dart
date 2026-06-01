// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';

import '../../helpers/test_document_factory.dart';
import '../../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
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
}
