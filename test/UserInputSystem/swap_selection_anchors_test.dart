// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  group('swapSelectionAnchors', () {
    test('swaps anchor and extent of a range selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      // Create a range selection: anchor at 0, extent at 5.
      env.inputService.handleTextClick(doc.id, blockId, 0, 0);
      env.actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 0,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 5,
        ),
      );

      // Verify initial state.
      final before = doc.selection.value as RangeSelectionState;
      final anchorBefore = before.anchor as CursorPositionInTextBlock;
      final extentBefore = before.extent as CursorPositionInTextBlock;
      expect(anchorBefore.offset, 0);
      expect(extentBefore.offset, 5);

      // Swap.
      env.inputService.swapSelectionAnchors(doc.id);

      // Verify swapped.
      final after = doc.selection.value as RangeSelectionState;
      final anchorAfter = after.anchor as CursorPositionInTextBlock;
      final extentAfter = after.extent as CursorPositionInTextBlock;
      expect(anchorAfter.offset, 5, reason: 'former extent is now anchor');
      expect(extentAfter.offset, 0, reason: 'former anchor is now extent');
    });

    test('does nothing on SingleCursorSelectionState', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      final before = doc.selection.value;
      expect(before, isA<SingleCursorSelectionState>());

      env.inputService.swapSelectionAnchors(doc.id);

      final after = doc.selection.value;
      expect(after, isA<SingleCursorSelectionState>());
      expect(
        (after as SingleCursorSelectionState).cursorPos,
        (before as SingleCursorSelectionState).cursorPos,
      );
    });

    test('does nothing on NoSelectionState', () {
      final (doc, _) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      expect(doc.selection.value, isA<NoSelectionState>());

      env.inputService.swapSelectionAnchors(doc.id);

      expect(doc.selection.value, isA<NoSelectionState>());
    });

    test('swaps cross-block range selection', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second')],
      );
      env.documentsManager.openDocument(doc);

      env.actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 2,
          extentBlockId: 'b2',
          extentSegmentIndex: 0,
          extentOffset: 3,
        ),
      );

      env.inputService.swapSelectionAnchors(doc.id);

      final after = doc.selection.value as RangeSelectionState;
      final anchor = after.anchor as CursorPositionInTextBlock;
      final extent = after.extent as CursorPositionInTextBlock;

      expect(anchor.blockId, 'b2');
      expect(anchor.offset, 3);
      expect(extent.blockId, 'b1');
      expect(extent.offset, 2);
    });
  });
}
