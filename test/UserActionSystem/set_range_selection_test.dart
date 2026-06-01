// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

import '../helpers/test_document_factory.dart';

void main() {
  late OpenedDocumentsManager manager;
  late IdService idService;
  late UserActionService actionService;

  setUp(() {
    var idCounter = 0;
    idService = IdService(() => 'generated-id-${idCounter++}');
    manager = OpenedDocumentsManager();
    actionService = UserActionService(manager, idService);
  });

  // ---------------------------------------------------------------------------
  // SetRangeSelection
  // ---------------------------------------------------------------------------

  group('SetRangeSelection', () {
    test('creates range selection within a single block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 1,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 4,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.offset, 1);
      expect(extent.offset, 4);
    });

    test('creates range selection across blocks', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second')],
      );
      manager.openDocument(doc);

      actionService.handleAction(
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

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.blockId, 'b1');
      expect(anchor.offset, 2);
      expect(extent.blockId, 'b2');
      expect(extent.offset, 3);
    });

    test('collapses to single cursor when anchor equals extent', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 3,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 3,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
      final cursor =
          (sel as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      expect(cursor.offset, 3);
    });
  });
}
