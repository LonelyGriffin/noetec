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
  // SelectAll
  // ---------------------------------------------------------------------------

  group('SelectAll', () {
    test('selects entire single block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(SelectAll(documentId: doc.id));

      final sel = doc.selection.value;
      expect(sel, isA<RangeSelectionState>());
      final range = sel as RangeSelectionState;

      final anchor = range.anchor as CursorPositionInTextBlock;
      expect(anchor.blockId, blockId);
      expect(anchor.offset, 0);

      final extent = range.extent as CursorPositionInTextBlock;
      expect(extent.blockId, blockId);
      expect(extent.offset, 5);
    });

    test('selects from first block to last block in multi-block document', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second'), ('b3', 'Third')],
      );
      manager.openDocument(doc);

      actionService.handleAction(SelectAll(documentId: doc.id));

      final range = doc.selection.value as RangeSelectionState;
      final anchor = range.anchor as CursorPositionInTextBlock;
      final extent = range.extent as CursorPositionInTextBlock;

      expect(anchor.blockId, 'b1');
      expect(anchor.offset, 0);
      expect(extent.blockId, 'b3');
      expect(extent.offset, 5, reason: '"Third" has length 5');
    });

    test('collapses to cursor on single empty block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: '');
      manager.openDocument(doc);

      actionService.handleAction(SelectAll(documentId: doc.id));

      final sel = doc.selection.value;
      expect(sel, isA<SingleCursorSelectionState>());
    });
  });
}
