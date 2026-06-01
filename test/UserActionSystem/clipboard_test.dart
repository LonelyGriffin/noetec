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
  // extractSelectedMarkdown
  // ---------------------------------------------------------------------------

  group('extractSelectedMarkdown', () {
    test('returns null when no range selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      expect(actionService.extractSelectedMarkdown(doc.id), isNull);
    });

    test('extracts markdown for single-block selection', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 6,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 11,
        ),
      );

      final md = actionService.extractSelectedMarkdown(doc.id);
      expect(md, isNotNull);
      expect(md, contains('World'));
    });

    test('extracts markdown for multi-block selection', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'First'), ('b2', 'Second')],
      );
      manager.openDocument(doc);

      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: 'b1',
          anchorSegmentIndex: 0,
          anchorOffset: 0,
          extentBlockId: 'b2',
          extentSegmentIndex: 0,
          extentOffset: 6,
        ),
      );

      final md = actionService.extractSelectedMarkdown(doc.id);
      expect(md, isNotNull);
      expect(md, contains('First'));
      expect(md, contains('Second'));
    });
  });

  // ---------------------------------------------------------------------------
  // Paste — single block
  // ---------------------------------------------------------------------------

  group('Paste — single block inline', () {
    test('pastes plain text at cursor position', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 5,
        ),
      );

      actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: 'Beautiful'),
      );

      expect(blockText(doc, blockId), 'HelloBeautiful World');
      final cursor =
          (doc.selection.value as SingleCursorSelectionState).cursorPos
              as CursorPositionInTextBlock;
      final block = doc.getBlockById(blockId) as TextBlock;
      expect(
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset),
        14,
        reason: 'Cursor after "Beautiful" (5 + 9)',
      );
    });

    test('pastes formatted markdown as formatted segments', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'AB');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 1,
        ),
      );

      actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: '**bold**'),
      );

      // Should have: "A" + "bold" (bold) + "B"
      final block = doc.getBlockById(blockId) as TextBlock;
      final segs = block.segments.value;
      expect(block.computeAllSegmentsText(), 'AboldB');
      // Find bold segment.
      final boldSegs = segs
          .where((s) => s is FormattedSegment && s.format == TextFormat.bold)
          .toList();
      expect(boldSegs.length, 1);
      expect(boldSegs.first.text, 'bold');
    });
  });

  // ---------------------------------------------------------------------------
  // Paste — multi-block
  // ---------------------------------------------------------------------------

  group('Paste — multi-block', () {
    test('pastes multiple paragraphs splitting current block', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'AABB');
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: blockId,
          segmentIndex: 0,
          offset: 2,
        ),
      );

      actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: 'First\n\nSecond'),
      );

      // Should result in 2 blocks: "AAFirst" and "SecondBB".
      expect(doc.rootBlocks.length, 2);
      expect(
        (doc.rootBlocks[0] as TextBlock).computeAllSegmentsText(),
        'AAFirst',
      );
      expect(
        (doc.rootBlocks[1] as TextBlock).computeAllSegmentsText(),
        'SecondBB',
      );
    });

    test('pastes with active range selection (delete first)', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      manager.openDocument(doc);

      // Select "lo Wo" (3..8).
      actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 3,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 8,
        ),
      );

      actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: 'XY'),
      );

      expect(blockText(doc, blockId), 'HelXYrld');
    });
  });

  // ---------------------------------------------------------------------------
  // Paste — fenced directives (new IDs)
  // ---------------------------------------------------------------------------

  group('Paste — fenced directives', () {
    test('pasted blocks with existing IDs get new IDs (always new on paste)', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [('b1', 'Existing')],
      );
      manager.openDocument(doc);

      actionService.handleAction(
        ClickOnTextBlock(
          documentId: doc.id,
          blockId: 'b1',
          segmentIndex: 0,
          offset: 8,
        ),
      );

      // Paste markdown with a fenced directive whose ID matches an existing block.
      // Since we always generate new IDs on paste, the ID should differ.
      actionService.handleAction(
        Paste(documentId: doc.id, clipboardContent: '::: {#b1}\nPasted\n:::'),
      );

      // The pasted content should be inlined (single block paste).
      expect(blockText(doc, 'b1'), 'ExistingPasted');
    });
  });
}
