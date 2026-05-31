// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Integration tests for cross-block cursor navigation via arrow keys.
///
/// When the cursor is at the very start of a block and the user presses
/// ArrowLeft, the cursor should move to the end of the previous block.
/// When the cursor is at the very end of a block and the user presses
/// ArrowRight, the cursor should move to the start of the next block.
///
/// NOTE: These tests describe the EXPECTED behaviour. The feature is not yet
/// implemented in [UserActionService._handleMoveCursor] — it currently clamps
/// the cursor at the block boundary and does nothing. All tests in this file
/// will FAIL until the implementation is added.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Dispatches an ArrowLeft key event.
void _pressArrowLeft(TestEnvironment env, String documentId) {
  env.inputService.handleKeyEvent(
    documentId,
    KeyDownEvent(
      logicalKey: LogicalKeyboardKey.arrowLeft,
      physicalKey: PhysicalKeyboardKey.arrowLeft,
      timeStamp: Duration.zero,
    ),
  );
}

/// Dispatches an ArrowRight key event.
void _pressArrowRight(TestEnvironment env, String documentId) {
  env.inputService.handleKeyEvent(
    documentId,
    KeyDownEvent(
      logicalKey: LogicalKeyboardKey.arrowRight,
      physicalKey: PhysicalKeyboardKey.arrowRight,
      timeStamp: Duration.zero,
    ),
  );
}

/// Dispatches a character key event.
void _pressCharacter(TestEnvironment env, String documentId, String char) {
  env.inputService.handleKeyEvent(
    documentId,
    KeyDownEvent(
      logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
      physicalKey: PhysicalKeyboardKey.keyA,
      character: char,
      timeStamp: Duration.zero,
    ),
  );
}

/// Returns the flat cursor offset within the currently focused block.
/// Throws if there is no single-cursor selection.
int _cursorFlatOffset(
  DocumentModel doc,
  TextBlock block,
) {
  final cursor = (doc.selection.value as SingleCursorSelectionState).cursorPos
      as CursorPositionInTextBlock;
  return block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);
}

/// Returns the [CursorPositionInTextBlock] from the current selection.
CursorPositionInTextBlock _cursorPos(DocumentModel doc) {
  return (doc.selection.value as SingleCursorSelectionState).cursorPos
      as CursorPositionInTextBlock;
}

// ---------------------------------------------------------------------------

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // ArrowLeft at the start of a block → jump to end of previous block
  // ---------------------------------------------------------------------------
  group('ArrowLeft at block start — jump to previous block', () {
    test(
      'cursor at start of second block jumps to end of first block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Place cursor at the very start of block-2.
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressArrowLeft(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(
          cursor.blockId,
          'block-1',
          reason: 'ArrowLeft at start of block-2 should jump to block-1',
        );

        final block1 = doc.getBlockById('block-1') as TextBlock;
        final flat = _cursorFlatOffset(doc, block1);
        expect(
          flat,
          'First'.length, // 5
          reason: 'Cursor should land at the end of block-1 text',
        );
      },
    );

    test(
      'cursor at start of third block jumps to end of second block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Alpha'),
            ('block-2', 'Beta'),
            ('block-3', 'Gamma'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-3', 0, 0);

        _pressArrowLeft(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-2');

        final block2 = doc.getBlockById('block-2') as TextBlock;
        final flat = _cursorFlatOffset(doc, block2);
        expect(flat, 'Beta'.length); // 4
      },
    );

    test(
      'ArrowLeft at start of the first block does not move cursor',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-1', 0, 0);

        _pressArrowLeft(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(
          cursor.blockId,
          'block-1',
          reason: 'No previous block — cursor must stay in block-1',
        );

        final block1 = doc.getBlockById('block-1') as TextBlock;
        final flat = _cursorFlatOffset(doc, block1);
        expect(flat, 0, reason: 'Cursor must stay at offset 0');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // ArrowRight at the end of a block → jump to start of next block
  // ---------------------------------------------------------------------------
  group('ArrowRight at block end — jump to next block', () {
    test(
      'cursor at end of first block jumps to start of second block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Place cursor at the very end of block-1.
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'First'.length);

        _pressArrowRight(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(
          cursor.blockId,
          'block-2',
          reason: 'ArrowRight at end of block-1 should jump to block-2',
        );

        final block2 = doc.getBlockById('block-2') as TextBlock;
        final flat = _cursorFlatOffset(doc, block2);
        expect(flat, 0, reason: 'Cursor should land at offset 0 of block-2');
      },
    );

    test(
      'cursor at end of second block jumps to start of third block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Alpha'),
            ('block-2', 'Beta'),
            ('block-3', 'Gamma'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-2', 0, 'Beta'.length);

        _pressArrowRight(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-3');

        final block3 = doc.getBlockById('block-3') as TextBlock;
        final flat = _cursorFlatOffset(doc, block3);
        expect(flat, 0);
      },
    );

    test(
      'ArrowRight at end of the last block does not move cursor',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'Hello'),
            ('block-2', 'World'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(
            doc.id, 'block-2', 0, 'World'.length);

        _pressArrowRight(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(
          cursor.blockId,
          'block-2',
          reason: 'No next block — cursor must stay in block-2',
        );

        final block2 = doc.getBlockById('block-2') as TextBlock;
        final flat = _cursorFlatOffset(doc, block2);
        expect(flat, 'World'.length, reason: 'Cursor must stay at end');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // IME state synchronisation on cross-block navigation
  // ---------------------------------------------------------------------------
  group('IME state after cross-block navigation', () {
    test(
      'ArrowLeft to previous block: IME text = previous block text, '
      'selection offset = end of that text',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);

        _pressArrowLeft(env, doc.id);

        final imeState = env.inputService.getImeState(doc.id).value;
        expect(
          imeState.text,
          'First',
          reason:
              'After jumping to block-1, IME text must equal block-1 content',
        );
        expect(
          imeState.selection,
          const TextSelection.collapsed(offset: 5),
          reason: 'IME cursor must be at the end of "First" (offset 5)',
        );
      },
    );

    test(
      'ArrowRight to next block: IME text = next block text, '
      'selection offset = 0',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'First'.length);

        _pressArrowRight(env, doc.id);

        final imeState = env.inputService.getImeState(doc.id).value;
        expect(
          imeState.text,
          'Second',
          reason:
              'After jumping to block-2, IME text must equal block-2 content',
        );
        expect(
          imeState.selection,
          const TextSelection.collapsed(offset: 0),
          reason: 'IME cursor must be at the start of "Second" (offset 0)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Typing after cross-block navigation inserts text in the correct block
  // ---------------------------------------------------------------------------
  group('typing after cross-block navigation', () {
    test(
      'ArrowRight to next block then type inserts into next block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-1 → jump right to start of block-2 → type 'X'
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 'First'.length);
        _pressArrowRight(env, doc.id);
        _pressCharacter(env, doc.id, 'X');

        expect(
          blockText(doc, 'block-1'),
          'First',
          reason: 'block-1 must be unmodified',
        );
        expect(
          blockText(doc, 'block-2'),
          'XSecond',
          reason: 'X must be inserted at the start of block-2',
        );
      },
    );

    test(
      'ArrowLeft to previous block then type inserts into previous block',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'First'),
            ('block-2', 'Second'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-2 → jump left to end of block-1 → type 'X'
        env.inputService.handleTextClick(doc.id, 'block-2', 0, 0);
        _pressArrowLeft(env, doc.id);
        _pressCharacter(env, doc.id, 'X');

        expect(
          blockText(doc, 'block-1'),
          'FirstX',
          reason: 'X must be appended to block-1',
        );
        expect(
          blockText(doc, 'block-2'),
          'Second',
          reason: 'block-2 must be unmodified',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Multiple consecutive cross-block jumps
  // ---------------------------------------------------------------------------
  group('multiple consecutive cross-block jumps', () {
    test(
      'ArrowRight × 2 from end of first block crosses two boundaries',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'A'),
            ('block-2', 'B'),
            ('block-3', 'C'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at end of block-1 ('A', length 1)
        env.inputService.handleTextClick(doc.id, 'block-1', 0, 1);

        _pressArrowRight(env, doc.id); // → start of block-2

        // Cursor is now at block-2 offset 0; need to move to end of block-2
        // to allow a second cross-block jump.
        // Press Right one more time from offset 0 → offset 1 (inside block-2)
        _pressArrowRight(env, doc.id); // → end of block-2 (offset 1 = length of 'B')

        // Now press Right once more from the end of block-2 → start of block-3
        _pressArrowRight(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-3');

        final block3 = doc.getBlockById('block-3') as TextBlock;
        final flat = _cursorFlatOffset(doc, block3);
        expect(flat, 0);
      },
    );

    test(
      'ArrowLeft × 2 from start of third block crosses two boundaries',
      () {
        final (doc, _) = createMultiBlockDocument(
          blocks: [
            ('block-1', 'A'),
            ('block-2', 'B'),
            ('block-3', 'C'),
          ],
        );
        env.documentsManager.openDocument(doc);

        // Cursor at start of block-3
        env.inputService.handleTextClick(doc.id, 'block-3', 0, 0);

        _pressArrowLeft(env, doc.id); // → end of block-2

        // Now at end of block-2 (offset 1). Press Left once → offset 0 of block-2.
        _pressArrowLeft(env, doc.id); // → offset 0 of block-2

        // Now at start of block-2. Press Left → end of block-1.
        _pressArrowLeft(env, doc.id);

        final cursor = _cursorPos(doc);
        expect(cursor.blockId, 'block-1');

        final block1 = doc.getBlockById('block-1') as TextBlock;
        final flat = _cursorFlatOffset(doc, block1);
        expect(flat, 'A'.length); // 1
      },
    );
  });
}
