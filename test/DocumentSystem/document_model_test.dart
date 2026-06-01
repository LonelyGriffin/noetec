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
  // ---------------------------------------------------------------------------
  // DocumentModel.addBlock
  // ---------------------------------------------------------------------------
  group('DocumentModel.addBlock', () {
    test('adds block to rootBlocks and makes it retrievable by ID', () {
      final (doc, blockId) = createSingleSegmentDocument();

      expect(doc.rootBlocks.value.length, 1);
      expect(doc.getBlockById(blockId), isNotNull);
      expect(doc.getBlockById(blockId), isA<TextBlock>());
    });

    test('multiple blocks are in correct order', () {
      final (doc, blockIds) = createMultiBlockDocument();

      expect(doc.rootBlocks.value.length, 3);
      expect(doc.rootBlocks.value[0].id, blockIds[0]);
      expect(doc.rootBlocks.value[1].id, blockIds[1]);
      expect(doc.rootBlocks.value[2].id, blockIds[2]);
    });
  });

  // ---------------------------------------------------------------------------
  // DocumentModel.computeTextEditingValue
  // ---------------------------------------------------------------------------
  group('DocumentModel.computeTextEditingValue', () {
    test('returns empty when no selection', () {
      final (doc, _) = createSingleSegmentDocument(text: 'Hello');

      final tev = doc.computeTextEditingValue();
      expect(tev, TextEditingValue.empty);
    });

    test('returns correct value for cursor in single-segment block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');

      doc.selection.value = SingleCursorSelectionState(
        cursorPos: CursorPositionInTextBlock(
          blockId: blockId,
          segmentIndex: 0,
          offset: 3,
        ),
      );

      final tev = doc.computeTextEditingValue();
      expect(tev.text, 'Hello');
      expect(tev.selection, const TextSelection.collapsed(offset: 3));
    });

    test('returns correct value for cursor in multi-segment block', () {
      final (doc, blockId) = createMultiSegmentDocument();
      // "Hello " (6) + "bold" (4) + " world" (6) = "Hello bold world"

      doc.selection.value = SingleCursorSelectionState(
        cursorPos: CursorPositionInTextBlock(
          blockId: blockId,
          segmentIndex: 1,
          offset: 2,
        ),
      );

      final tev = doc.computeTextEditingValue();
      expect(tev.text, 'Hello bold world');
      expect(tev.selection, const TextSelection.collapsed(offset: 8)); // 6 + 2
    });

    test('cursor at start of block produces offset 0', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');

      doc.selection.value = SingleCursorSelectionState(
        cursorPos: CursorPositionInTextBlock(
          blockId: blockId,
          segmentIndex: 0,
          offset: 0,
        ),
      );

      final tev = doc.computeTextEditingValue();
      expect(tev.selection, const TextSelection.collapsed(offset: 0));
    });

    test('cursor at end of block produces offset equal to text length', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');

      doc.selection.value = SingleCursorSelectionState(
        cursorPos: CursorPositionInTextBlock(
          blockId: blockId,
          segmentIndex: 0,
          offset: 5,
        ),
      );

      final tev = doc.computeTextEditingValue();
      expect(tev.selection, const TextSelection.collapsed(offset: 5));
    });
  });
}
