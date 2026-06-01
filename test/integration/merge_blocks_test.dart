// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Integration tests for block merging via Delete and Backspace keys.
///
/// Rules under test:
///   • Delete at the end of a block merges it with the next text block.
///   • Backspace at the start of a block merges it with the previous text
///     block.
///   • If both blocks contain text, they are replaced by a single new block
///     whose ID comes from [IdService], and both original IDs are gone.
///   • If one of the two blocks is empty, it is simply removed; the non-empty
///     block keeps its ID and the cursor moves to the appropriate position.
///   • Delete/Backspace at the document boundary (no next/previous block) is a
///     no-op.
///
/// NOTE: These tests describe the EXPECTED behaviour. The merge feature is not
/// yet implemented — [UserInputService._handleDelete] and
/// [UserInputService._handleBackspace] currently return early at block
/// boundaries. All tests in this file will FAIL until the implementation is
/// added.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _pressDelete(TestEnvironment env, String documentId) {
  env.inputService.handleKeyEvent(
    documentId,
    KeyDownEvent(
      logicalKey: LogicalKeyboardKey.delete,
      physicalKey: PhysicalKeyboardKey.delete,
      timeStamp: Duration.zero,
    ),
  );
}

void _pressBackspace(TestEnvironment env, String documentId) {
  env.inputService.handleKeyEvent(
    documentId,
    KeyDownEvent(
      logicalKey: LogicalKeyboardKey.backspace,
      physicalKey: PhysicalKeyboardKey.backspace,
      timeStamp: Duration.zero,
    ),
  );
}

CursorPositionInTextBlock _cursorPos(dynamic doc) {
  return (doc.selection.value as SingleCursorSelectionState).cursorPos
      as CursorPositionInTextBlock;
}

int _cursorFlatOffset(dynamic doc, TextBlock block) {
  final cursor = _cursorPos(doc);
  return block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);
}

// ---------------------------------------------------------------------------

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Delete at end of block
  // ---------------------------------------------------------------------------
  group('Delete at end of block — merge with next block', () {
    test(
      'both blocks non-empty: merged text, cursor block (block-1) keeps its ID, '
      'other block (block-2) removed',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-1.
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'Hello'.length);

        _pressDelete(env, doc.id);

        expect(doc.rootBlocks.length, 1,
            reason: 'Two blocks should merge into one');

        final merged = doc.rootBlocks[0] as TextBlock;
        expect(merged.computeAllSegmentsText(), 'HelloWorld');

        // Cursor block (block-1) keeps its ID.
        expect(merged.id, 'block-1');

        // The other block must be gone.
        expect(doc.getBlockById('block-2'), isNull);
      },
    );

    test(
      'current block empty: empty block removed, next block keeps its ID, '
      'cursor at offset 0 of next block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', ''),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor in the empty block-1 at offset 0.
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 0);

        _pressDelete(env, doc.id);

        expect(doc.rootBlocks.length, 1);

        final remaining = doc.rootBlocks[0] as TextBlock;
        expect(remaining.id, 'block-2',
            reason: 'Non-empty block-2 must keep its ID');
        expect(remaining.computeAllSegmentsText(), 'World');

        expect(doc.getBlockById('block-1'), isNull,
            reason: 'Empty block-1 must be removed');

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-2');
        expect(_cursorFlatOffset(doc, remaining), 0);
      },
    );

    test(
      'next block empty: empty next block removed, current block keeps its ID, '
      'cursor stays at end of current block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', ''),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-1.
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'Hello'.length);

        _pressDelete(env, doc.id);

        expect(doc.rootBlocks.length, 1);

        final remaining = doc.rootBlocks[0] as TextBlock;
        expect(remaining.id, 'block-1',
            reason: 'Non-empty block-1 must keep its ID');
        expect(remaining.computeAllSegmentsText(), 'Hello');

        expect(doc.getBlockById('block-2'), isNull,
            reason: 'Empty block-2 must be removed');

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-1');
        expect(_cursorFlatOffset(doc, remaining), 'Hello'.length);
      },
    );

    test(
      'Delete at end of last block is a no-op',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-2 (the last block).
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 'World'.length);

        _pressDelete(env, doc.id);

        expect(doc.rootBlocks.length, 2,
            reason: 'No next block — nothing should change');
        expect(blockText(doc, 'block-1'), 'Hello');
        expect(blockText(doc, 'block-2'), 'World');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Backspace at start of block
  // ---------------------------------------------------------------------------
  group('Backspace at start of block — merge with previous block', () {
    test(
      'both blocks non-empty: merged text, cursor block (block-2) keeps its ID, '
      'other block (block-1) removed',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-2.
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        expect(doc.rootBlocks.length, 1,
            reason: 'Two blocks should merge into one');

        final merged = doc.rootBlocks[0] as TextBlock;
        expect(merged.computeAllSegmentsText(), 'HelloWorld');

        // Cursor block (block-2) keeps its ID.
        expect(merged.id, 'block-2');

        // The other block must be gone.
        expect(doc.getBlockById('block-1'), isNull);
      },
    );

    test(
      'previous block empty: empty block removed, current block keeps its ID, '
      'cursor stays at offset 0',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', ''),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-2.
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        expect(doc.rootBlocks.length, 1);

        final remaining = doc.rootBlocks[0] as TextBlock;
        expect(remaining.id, 'block-2',
            reason: 'Non-empty block-2 must keep its ID');
        expect(remaining.computeAllSegmentsText(), 'World');

        expect(doc.getBlockById('block-1'), isNull,
            reason: 'Empty block-1 must be removed');

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-2');
        expect(_cursorFlatOffset(doc, remaining), 0);
      },
    );

    test(
      'current block empty: empty block removed, previous block keeps its ID, '
      'cursor at end of previous block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', ''),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor in empty block-2 at offset 0.
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        expect(doc.rootBlocks.length, 1);

        final remaining = doc.rootBlocks[0] as TextBlock;
        expect(remaining.id, 'block-1',
            reason: 'Non-empty block-1 must keep its ID');
        expect(remaining.computeAllSegmentsText(), 'Hello');

        expect(doc.getBlockById('block-2'), isNull,
            reason: 'Empty block-2 must be removed');

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-1');
        expect(_cursorFlatOffset(doc, remaining), 'Hello'.length);
      },
    );

    test(
      'Backspace at start of first block is a no-op',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-1 (the first block).
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 0);

        _pressBackspace(env, doc.id);

        expect(doc.rootBlocks.length, 2,
            reason: 'No previous block — nothing should change');
        expect(blockText(doc, 'block-1'), 'Hello');
        expect(blockText(doc, 'block-2'), 'World');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Cursor position after merge
  // ---------------------------------------------------------------------------
  group('Cursor position after merge', () {
    test(
      'Delete merges two non-empty blocks: cursor lands at the join point '
      '(offset = length of left block text)',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'Hello'.length);

        _pressDelete(env, doc.id);

        // block-1 is the cursor block and keeps its ID.
        final merged = doc.getBlockById('block-1') as TextBlock;
        expect(
          _cursorFlatOffset(doc, merged),
          'Hello'.length,
          reason: 'Cursor must sit at the join point between the two texts',
        );
      },
    );

    test(
      'Backspace merges two non-empty blocks: cursor lands at the join point '
      '(offset = length of left block text)',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        // block-2 is the cursor block and keeps its ID.
        final merged = doc.getBlockById('block-2') as TextBlock;
        expect(
          _cursorFlatOffset(doc, merged),
          'Hello'.length,
          reason: 'Cursor must sit at the join point between the two texts',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // IME state after merge
  // ---------------------------------------------------------------------------
  group('IME state after merge', () {
    test(
      'Delete merges two non-empty blocks: IME text equals merged text, '
      'IME cursor at join point',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'Hello'.length);

        _pressDelete(env, doc.id);

        final imeState = env.inputService.getImeState(doc.id).value;
        expect(imeState.text, 'HelloWorld');
        expect(
          imeState.selection,
          const TextSelection.collapsed(offset: 5),
          reason: 'IME cursor must be at the join point (offset 5)',
        );
      },
    );

    test(
      'Backspace merges two non-empty blocks: IME text equals merged text, '
      'IME cursor at join point',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        final imeState = env.inputService.getImeState(doc.id).value;
        expect(imeState.text, 'HelloWorld');
        expect(
          imeState.selection,
          const TextSelection.collapsed(offset: 5),
          reason: 'IME cursor must be at the join point (offset 5)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Segment preservation on merge
  // ---------------------------------------------------------------------------
  group('Segment preservation on merge', () {
    test(
      'Delete: multi-segment block-1 merged with plain block-2 — all segments '
      'preserved in correct order with correct types',
      () {
        // block-1: "Hello " (plain) + "bold" (bold)
        // block-2: " world" (plain)
        final (doc, _) = createMultiSegmentDocument(
          blockId: 'block-1',
          segments: [
            const TextSegment(text: 'Hello '),
            const FormattedSegment(text: 'bold', format: TextFormat.bold),
          ],
        );
        final block2 = TextBlock(
          id: 'block-2',
          documentId: doc.id,
          parent: ValueNotifier(null),
          segments: ListNotifier(data: [const TextSegment(text: ' world')]),
        );
        doc.addBlock(block2, 1);
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-1: segmentIndex=1, offset=4 ("bold".length).
        env.inputService.handleTextClick(doc.id, 'block-1', 1, 'bold'.length);

        _pressDelete(env, doc.id);

        expect(doc.rootBlocks.length, 1);
        final merged = doc.rootBlocks[0] as TextBlock;
        expect(merged.computeAllSegmentsText(), 'Hello bold world');

        final segs = merged.segments.value;
        expect(segs.length, 3);

        expect(segs[0], isNot(isA<FormattedSegment>()));
        expect(segs[0].text, 'Hello ');

        expect(segs[1], isA<FormattedSegment>());
        expect((segs[1] as FormattedSegment).format, TextFormat.bold);
        expect(segs[1].text, 'bold');

        expect(segs[2], isNot(isA<FormattedSegment>()));
        expect(segs[2].text, ' world');
      },
    );

    test(
      'Backspace: plain block-1 merged with multi-segment block-2 — all '
      'segments preserved in correct order with correct types',
      () {
        // block-1: "Hello " (plain)
        // block-2: "bold" (bold) + " world" (plain)
        final (doc, _) = createSingleSegmentDocument(
          blockId: 'block-1',
          text: 'Hello ',
        );
        final block2 = TextBlock(
          id: 'block-2',
          documentId: doc.id,
          parent: ValueNotifier(null),
          segments: ListNotifier(data: [
            const FormattedSegment(text: 'bold', format: TextFormat.bold),
            const TextSegment(text: ' world'),
          ]),
        );
        doc.addBlock(block2, 1);
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-2.
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressBackspace(env, doc.id);

        expect(doc.rootBlocks.length, 1);
        final merged = doc.rootBlocks[0] as TextBlock;
        expect(merged.computeAllSegmentsText(), 'Hello bold world');

        final segs = merged.segments.value;
        expect(segs.length, 3);

        expect(segs[0], isNot(isA<FormattedSegment>()));
        expect(segs[0].text, 'Hello ');

        expect(segs[1], isA<FormattedSegment>());
        expect((segs[1] as FormattedSegment).format, TextFormat.bold);
        expect(segs[1].text, 'bold');

        expect(segs[2], isNot(isA<FormattedSegment>()));
        expect(segs[2].text, ' world');
      },
    );
  });
}
