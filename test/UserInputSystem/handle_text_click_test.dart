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
}
