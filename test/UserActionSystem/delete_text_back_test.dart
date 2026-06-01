// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
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
  // DeleteTextBack
  // ---------------------------------------------------------------------------
  group('DeleteTextBack', () {
    test('deletes character before cursor in middle of text', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 3,
      ));

      expect(blockText(doc, blockId), 'Helo');
    });

    test('does nothing when flatOffset is 0', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 0,
      ));

      expect(blockText(doc, blockId), 'Hello');
    });

    test('deletes last character', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 5,
      ));

      expect(blockText(doc, blockId), 'Hell');
    });

    test('moves cursor back by one', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 3,
      ));

      final sel = doc.selection.value as SingleCursorSelectionState;
      final cursor = sel.cursorPos as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset), 2);
    });

    test('deletes from correct segment in multi-segment block', () {
      // "Hello " (6) + "bold" (4) + " world" (6) = 16
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Delete at flat offset 8 = "Hello " (6) + 2 into "bold" → deletes 'o'
      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 8,
      ));

      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[0], 'Hello ');
      expect(segTexts[1], 'bld');
      expect(segTexts[2], ' world');
    });

    test('preserves segment type on delete', () {
      final (doc, blockId) = createMultiSegmentDocument();
      manager.openDocument(doc);

      // Delete inside bold segment
      actionService.handleAction(DeleteTextBack(
        documentId: doc.id,
        blockId: blockId,
        flatOffset: 8,
      ));

      final block = doc.getBlockById(blockId) as TextBlock;
      final seg1 = block.segments.value[1];
      expect(seg1, isA<FormattedSegment>());
      expect((seg1 as FormattedSegment).format, TextFormat.bold);
    });
  });
}
