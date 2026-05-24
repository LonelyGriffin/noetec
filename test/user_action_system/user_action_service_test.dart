// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

import '../helpers/document_factory.dart';

void main() {
  late OpenedDocumentsManager manager;
  late UserActionService sut;
  late DocumentModel doc;

  setUp(() {
    manager = OpenedDocumentsManager();
    sut = UserActionService(manager);
    doc = makeDocument(id: 'doc1', manager: manager);
  });

  // ---------------------------------------------------------------------------
  // ClickOnTextBlock
  // ---------------------------------------------------------------------------

  group('ClickOnTextBlock', () {
    test('sets collapsed TextSelectionState on document', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');

      sut.handleAction(
        ClickOnTextBlock(
          documentId: 'doc1',
          blockId: 'b1',
          segmentIndex: 0,
          offset: 3,
        ),
      );

      final sel = doc.selection.value;
      expect(sel, isA<TextSelectionState>());
      sel as TextSelectionState;
      expect(sel.isCollapsed, isTrue);
      expect(sel.from.blockId, equals('b1'));
      expect(sel.from.segmentIndex, equals(0));
      expect(sel.from.offset, equals(3));
    });

    test('unknown documentId is a no-op (no exception)', () {
      expect(
        () => sut.handleAction(
          ClickOnTextBlock(
            documentId: 'no-such-doc',
            blockId: 'b1',
            segmentIndex: 0,
            offset: 0,
          ),
        ),
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ChangeTextSection
  // ---------------------------------------------------------------------------

  group('ChangeTextSection', () {
    test('replaces segments in the block', () {
      final block = makeTextBlock(document: doc, text: 'old text', id: 'b1');

      sut.handleAction(
        ChangeTextSection(
          documentId: 'doc1',
          blockId: 'b1',
          newSegments: [TextSegment(text: 'new text')],
          newSegmentIndex: 0,
          newOffset: 8,
        ),
      );

      expect(block.segments.value.length, equals(1));
      expect(block.segments.value.first.text, equals('new text'));
    });

    test('updates cursor after the edit', () {
      makeTextBlock(document: doc, text: 'hello world', id: 'b1');

      sut.handleAction(
        ChangeTextSection(
          documentId: 'doc1',
          blockId: 'b1',
          newSegments: [TextSegment(text: 'hello world!')],
          newSegmentIndex: 0,
          newOffset: 12,
        ),
      );

      final sel = doc.selection.value as TextSelectionState;
      expect(sel.from.segmentIndex, equals(0));
      expect(sel.from.offset, equals(12));
    });

    test('replaces multiple segments', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'hello '),
          FormattedSegment(text: 'world', format: TextFormat.bold),
        ],
      );

      sut.handleAction(
        ChangeTextSection(
          documentId: 'doc1',
          blockId: 'b1',
          newSegments: [
            TextSegment(text: 'hi '),
            FormattedSegment(text: 'there', format: TextFormat.bold),
          ],
          newSegmentIndex: 1,
          newOffset: 5,
        ),
      );

      expect(block.segments.value[0].text, equals('hi '));
      expect(block.segments.value[1].text, equals('there'));
      expect((block.segments.value[1] as FormattedSegment).format,
          equals(TextFormat.bold));
    });

    test('unknown documentId is a no-op', () {
      expect(
        () => sut.handleAction(
          ChangeTextSection(
            documentId: 'no-such-doc',
            blockId: 'b1',
            newSegments: [TextSegment(text: 'x')],
            newSegmentIndex: 0,
            newOffset: 1,
          ),
        ),
        returnsNormally,
      );
    });

    test('unknown blockId is a no-op', () {
      makeDocument(id: 'doc1', manager: manager);

      expect(
        () => sut.handleAction(
          ChangeTextSection(
            documentId: 'doc1',
            blockId: 'no-such-block',
            newSegments: [TextSegment(text: 'x')],
            newSegmentIndex: 0,
            newOffset: 1,
          ),
        ),
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SplitTextBlock
  // ---------------------------------------------------------------------------

  group('SplitTextBlock', () {
    test('splits flat text into two blocks at the given offset', () {
      final block = makeTextBlock(document: doc, text: 'helloworld', id: 'b1');

      sut.handleAction(
        SplitTextBlock(
          documentId: 'doc1',
          blockId: 'b1',
          splitFlatOffset: 5,
        ),
      );

      expect(block.flatText, equals('hello'));
      expect(doc.rootBlocks.value.length, equals(2));
      final newBlock = doc.rootBlocks.value[1] as TextBlock;
      expect(newBlock.flatText, equals('world'));
    });

    test('cursor moves to offset 0 of the new block', () {
      makeTextBlock(document: doc, text: 'helloworld', id: 'b1');

      sut.handleAction(
        SplitTextBlock(
          documentId: 'doc1',
          blockId: 'b1',
          splitFlatOffset: 5,
        ),
      );

      final sel = doc.selection.value as TextSelectionState;
      final newBlock = doc.rootBlocks.value[1];
      expect(sel.from.blockId, equals(newBlock.id));
      expect(sel.from.segmentIndex, equals(0));
      expect(sel.from.offset, equals(0));
    });

    test('split at offset 0 — first block empty, second gets all text', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 0),
      );

      expect(block.flatText, equals(''));
      final newBlock = doc.rootBlocks.value[1] as TextBlock;
      expect(newBlock.flatText, equals('hello'));
    });

    test('split at end — first block gets all text, second empty', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 5),
      );

      expect(block.flatText, equals('hello'));
      final newBlock = doc.rootBlocks.value[1] as TextBlock;
      expect(newBlock.flatText, equals(''));
    });

    test('split inside FormattedSegment preserves format in both halves', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          FormattedSegment(text: 'boldtext', format: TextFormat.bold),
        ],
      );

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 4),
      );

      // First block: "bold"
      expect(block.segments.value.length, equals(1));
      final beforeSeg = block.segments.value.first as FormattedSegment;
      expect(beforeSeg.text, equals('bold'));
      expect(beforeSeg.format, equals(TextFormat.bold));

      // Second block: "text"
      final newBlock = doc.rootBlocks.value[1] as TextBlock;
      expect(newBlock.segments.value.length, equals(1));
      final afterSeg = newBlock.segments.value.first as FormattedSegment;
      expect(afterSeg.text, equals('text'));
      expect(afterSeg.format, equals(TextFormat.bold));
    });

    test('split inside LinkSegment preserves url in both halves', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          LinkSegment(text: 'clickhere', url: 'https://example.com'),
        ],
      );

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 5),
      );

      final beforeSeg = block.segments.value.first as LinkSegment;
      expect(beforeSeg.text, equals('click'));
      expect(beforeSeg.url, equals('https://example.com'));

      final newBlock = doc.rootBlocks.value[1] as TextBlock;
      final afterSeg = newBlock.segments.value.first as LinkSegment;
      expect(afterSeg.text, equals('here'));
      expect(afterSeg.url, equals('https://example.com'));
    });

    test('split across multiple segments distributes them correctly', () {
      // "hello "(plain) + "world"(bold)  — split at 8 = inside "world" at [2]
      makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'hello '),
          FormattedSegment(text: 'world', format: TextFormat.bold),
        ],
      );

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 8),
      );

      final firstBlock = doc.rootBlocks.value[0] as TextBlock;
      // "hello " + "wo"
      expect(firstBlock.flatText, equals('hello wo'));

      final secondBlock = doc.rootBlocks.value[1] as TextBlock;
      // "rld"
      expect(secondBlock.flatText, equals('rld'));
      expect(
        (secondBlock.segments.value.first as FormattedSegment).format,
        equals(TextFormat.bold),
      );
    });

    test('new block is inserted immediately after the original', () {
      makeTextBlock(document: doc, text: 'first', id: 'b1');
      makeTextBlock(document: doc, text: 'third', id: 'b3', insertAt: 1);

      sut.handleAction(
        SplitTextBlock(documentId: 'doc1', blockId: 'b1', splitFlatOffset: 3),
      );

      expect(doc.rootBlocks.value.length, equals(3));
      // Original is at [0], new block at [1], "third" at [2].
      expect((doc.rootBlocks.value[0] as TextBlock).flatText, equals('fir'));
      expect((doc.rootBlocks.value[2] as TextBlock).flatText, equals('third'));
    });

    test('unknown documentId is a no-op', () {
      expect(
        () => sut.handleAction(
          SplitTextBlock(
            documentId: 'no-such-doc',
            blockId: 'b1',
            splitFlatOffset: 0,
          ),
        ),
        returnsNormally,
      );
    });
  });
}
