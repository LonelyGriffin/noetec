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
}
