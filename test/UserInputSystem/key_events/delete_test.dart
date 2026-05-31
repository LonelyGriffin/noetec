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
}
