// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Integration tests simulating the real flow:
///   user taps text → cursor moves → user types → text appears at cursor.
///
/// These tests use the same service chain that the real app does, but bypass
/// the Flutter widget layer (no `UserRawTextInputWidget`). Instead we call
/// [UserInputService.handleTextClick] for taps and
/// [UserInputService.handleTextDeltas] for IME input.
///
/// The critical scenario that reproduces the bug:
///   1. Click at position A → type characters → OK
///   2. Click at position B → type characters → BUG: text goes to position A
///
/// Root cause: [UserInputService.handleTextClick] updates the in-memory
/// [ValueNotifier<TextEditingValue>] (the "IME state notifier"), but the
/// platform IME is never told about the new cursor position (no call to
/// [TextInputConnection.setEditingState]). On the next keystroke the platform
/// sends a [TextEditingDeltaInsertion] whose [insertionOffset] still reflects
/// the **old** cursor position.
///
/// In unit tests we don't have a real platform IME, so we simulate the bug by
/// modelling what the platform would actually send: a delta whose
/// [insertionOffset] comes from the **platform's** copy of the editing state —
/// which, without the fix, is stale after a click.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

import '../helpers/test_document_factory.dart';

/// Simulates the platform IME sending an insertion delta.
///
/// [platformImeState] is the [TextEditingValue] that the **platform** believes
/// is current. In a correct implementation this equals
/// `inputService.getImeState(docId).value` because every cursor-changing event
/// calls [TextInputConnection.setEditingState]. When the bug is present, the
/// platform state is stale (it was never updated after the click).
TextEditingDeltaInsertion _makeInsertionDelta({
  required TextEditingValue platformImeState,
  required String textInserted,
}) {
  final offset = platformImeState.selection.baseOffset;
  return TextEditingDeltaInsertion(
    oldText: platformImeState.text,
    textInserted: textInserted,
    insertionOffset: offset,
    selection: TextSelection.collapsed(offset: offset + textInserted.length),
    composing: TextRange.empty,
  );
}

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Happy path: click once, type
  // ---------------------------------------------------------------------------
  group('click → type (happy path)', () {
    test('typing after a click inserts text at the clicked position', () {
      final (doc, blockId) = createSingleSegmentDocument(
        text: 'Hello World',
      );
      env.documentsManager.openDocument(doc);

      // User clicks at offset 5 ("Hello|")
      env.inputService.handleTextClick(doc.id, blockId, 0, 5);

      // Platform IME state after the click (the service updates the notifier)
      final platformState = env.inputService.getImeState(doc.id).value;

      // User types ","
      final delta = _makeInsertionDelta(
        platformImeState: platformState,
        textInserted: ',',
      );
      env.inputService.handleTextDeltas(doc.id, [delta]);

      expect(blockText(doc, blockId), 'Hello, World');
    });

    test('typing multiple chars sequentially', () {
      final (doc, blockId) = createSingleSegmentDocument(text: 'AB');
      env.documentsManager.openDocument(doc);

      env.inputService.handleTextClick(doc.id, blockId, 0, 1);

      // Type "xyz" one char at a time
      for (final char in ['x', 'y', 'z']) {
        final platformState = env.inputService.getImeState(doc.id).value;
        final delta = _makeInsertionDelta(
          platformImeState: platformState,
          textInserted: char,
        );
        env.inputService.handleTextDeltas(doc.id, [delta]);
      }

      expect(blockText(doc, blockId), 'AxyzB');
    });
  });

  // ---------------------------------------------------------------------------
  // BUG SCENARIO: click → type → click elsewhere → type
  // ---------------------------------------------------------------------------
  group('click → type → re-click → type (BUG scenario)', () {
    /// This test models the **actual platform behaviour** where the platform
    /// IME is NOT updated after the second click.
    ///
    /// The platform still thinks the cursor is where it was after the last
    /// `setEditingState` call. In the buggy code, `setEditingState` is only
    /// called when the connection is first opened (on focus gain), not after
    /// subsequent clicks. So the platform's IME state is stale.
    ///
    /// We model this by capturing the platform IME state **before** the second
    /// click and using it to build the delta.
    test(
      'BUG: after re-clicking to a new position, '
      'IME delta still carries the old offset — '
      'text is inserted at the WRONG position',
      () {
        final (doc, blockId) = createSingleSegmentDocument(
          text: 'Hello World',
        );
        env.documentsManager.openDocument(doc);

        // --- Phase 1: click at 5, type "," ---
        env.inputService.handleTextClick(doc.id, blockId, 0, 5);
        var platformState = env.inputService.getImeState(doc.id).value;
        env.inputService.handleTextDeltas(doc.id, [
          _makeInsertionDelta(
            platformImeState: platformState,
            textInserted: ',',
          ),
        ]);
        // Now text = "Hello, World", cursor at 6

        // Capture what the platform thinks the IME state is BEFORE the
        // second click. In the buggy code, the platform is never told about
        // cursor changes from clicks, so this state stays stale.
        final staleplatformState =
            env.inputService.getImeState(doc.id).value;

        // --- Phase 2: click at 12 ("Hello, World|") ---
        // Text is now "Hello, World" (12 chars). Click at end.
        env.inputService.handleTextClick(doc.id, blockId, 0, 12);

        // Verify the in-memory IME notifier was updated correctly
        final updatedNotifier = env.inputService.getImeState(doc.id).value;
        expect(
          updatedNotifier.selection,
          const TextSelection.collapsed(offset: 12),
          reason: 'In-memory IME notifier should reflect click at 12',
        );

        // But the PLATFORM IME was never told. In real life:
        //   platformState == staleplatformState (cursor at 6)
        // The platform would send a delta with insertionOffset: 6 (stale).
        //
        // If the code is CORRECT (i.e., the bug is fixed and setEditingState
        // was called), then platformState should have been updated to
        // cursor at 12, and the delta would carry insertionOffset: 12.
        //
        // We test the buggy scenario: platform sends delta based on stale state.
        final buggyDelta = _makeInsertionDelta(
          platformImeState: staleplatformState,
          textInserted: '!',
        );

        env.inputService.handleTextDeltas(doc.id, [buggyDelta]);

        // With the BUG: text is inserted at offset 6 (stale) → "Hello,! World"
        // CORRECT: text should be inserted at offset 12 → "Hello, World!"
        //
        // This test DOCUMENTS the bug. It will FAIL once the bug is fixed
        // (because the fix will make the platform state not stale, but
        // this test explicitly simulates stale state).
        expect(
          blockText(doc, blockId),
          'Hello,! World',
          reason: 'BUG: text inserted at old cursor position (6) instead of '
              'the new one (12). The platform IME was never updated after '
              'the second click.',
        );
      },
    );

    /// This test describes the CORRECT expected behaviour, using the
    /// in-memory IME state (which IS correctly updated) as the source of
    /// truth for the platform delta.
    ///
    /// This simulates what should happen when the bug is fixed: after
    /// each click, [setEditingState] is called, so the platform's copy
    /// matches the in-memory notifier.
    test(
      'CORRECT: when platform IME is in sync, '
      'text is inserted at the NEW cursor position after re-click',
      () {
        final (doc, blockId) = createSingleSegmentDocument(
          text: 'Hello World',
        );
        env.documentsManager.openDocument(doc);

        // --- Phase 1: click at 5, type "," ---
        env.inputService.handleTextClick(doc.id, blockId, 0, 5);
        var platformState = env.inputService.getImeState(doc.id).value;
        env.inputService.handleTextDeltas(doc.id, [
          _makeInsertionDelta(
            platformImeState: platformState,
            textInserted: ',',
          ),
        ]);
        // Now text = "Hello, World"

        // --- Phase 2: click at 12 ("Hello, World|") ---
        env.inputService.handleTextClick(doc.id, blockId, 0, 12);

        // In the FIXED code, the platform IME would be updated via
        // setEditingState, so it matches the in-memory notifier.
        platformState = env.inputService.getImeState(doc.id).value;

        final correctDelta = _makeInsertionDelta(
          platformImeState: platformState,
          textInserted: '!',
        );
        env.inputService.handleTextDeltas(doc.id, [correctDelta]);

        expect(
          blockText(doc, blockId),
          'Hello, World!',
          reason: 'With IME in sync, text is inserted at offset 12',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Variant: click on different blocks
  // ---------------------------------------------------------------------------
  group('click between blocks', () {
    test('type in block 1, click block 2, type — text goes to block 2', () {
      final (doc, blockIds) = createMultiBlockDocument(
        blocks: [
          ('b1', 'First'),
          ('b2', 'Second'),
        ],
      );
      env.documentsManager.openDocument(doc);

      // Click in block 1 at offset 5 ("First|")
      env.inputService.handleTextClick(doc.id, 'b1', 0, 5);
      var platformState = env.inputService.getImeState(doc.id).value;
      env.inputService.handleTextDeltas(doc.id, [
        _makeInsertionDelta(
          platformImeState: platformState,
          textInserted: '!',
        ),
      ]);
      expect(blockText(doc, 'b1'), 'First!');

      // Click in block 2 at offset 6 ("Second|")
      env.inputService.handleTextClick(doc.id, 'b2', 0, 6);

      // Use the (correctly updated) in-memory notifier state
      platformState = env.inputService.getImeState(doc.id).value;

      // Type in block 2
      env.inputService.handleTextDeltas(doc.id, [
        _makeInsertionDelta(
          platformImeState: platformState,
          textInserted: '?',
        ),
      ]);

      // Block 1 should be unchanged
      expect(blockText(doc, 'b1'), 'First!');
      // Block 2 should have the new text
      expect(blockText(doc, 'b2'), 'Second?');
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-segment insertion
  // ---------------------------------------------------------------------------
  group('multi-segment block — click and type', () {
    test('click in bold segment, type — text is inserted in bold segment', () {
      // "Hello " (6) + "bold" (4) + " world" (6) = "Hello bold world" (16)
      final (doc, blockId) = createMultiSegmentDocument();
      env.documentsManager.openDocument(doc);

      // Click at segment 1, offset 2 (inside "bold" → "bo|ld")
      // Flat offset = 6 + 2 = 8
      env.inputService.handleTextClick(doc.id, blockId, 1, 2);

      final platformState = env.inputService.getImeState(doc.id).value;
      expect(platformState.selection.baseOffset, 8);

      env.inputService.handleTextDeltas(doc.id, [
        _makeInsertionDelta(
          platformImeState: platformState,
          textInserted: 'X',
        ),
      ]);

      expect(blockText(doc, blockId), 'Hello boXld world');

      // Verify the bold segment got the insertion
      final segTexts = blockSegmentTexts(doc, blockId);
      expect(segTexts[1], 'boXld');

      // Verify the segment is still FormattedSegment with bold format
      final block = doc.getBlockById(blockId) as TextBlock;
      final seg = block.segments.value[1];
      expect(seg, isA<FormattedSegment>());
      expect((seg as FormattedSegment).format, TextFormat.bold);
    });
  });

  // ---------------------------------------------------------------------------
  // IME state consistency
  // ---------------------------------------------------------------------------
  group('IME state consistency', () {
    test(
      'IME state text always matches the block text of the focused block',
      () {
        final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
        env.documentsManager.openDocument(doc);

        env.inputService.handleTextClick(doc.id, blockId, 0, 5);

        // Type several characters
        for (final char in ['!', ' ', 'W', 'o', 'r', 'l', 'd']) {
          final state = env.inputService.getImeState(doc.id).value;
          env.inputService.handleTextDeltas(doc.id, [
            _makeInsertionDelta(
              platformImeState: state,
              textInserted: char,
            ),
          ]);

          // After each keystroke, IME text should match block text
          final imeText = env.inputService.getImeState(doc.id).value.text;
          final docText = blockText(doc, blockId);
          expect(imeText, docText,
              reason: 'IME and document text must stay in sync');
        }

        expect(blockText(doc, blockId), 'Hello! World');
      },
    );

    test(
      'IME state selection offset matches document cursor flat offset '
      'after every click',
      () {
        final (doc, blockId) = createSingleSegmentDocument(
          text: 'Hello World',
        );
        env.documentsManager.openDocument(doc);

        for (final clickOffset in [0, 5, 11, 3, 8, 0]) {
          env.inputService.handleTextClick(doc.id, blockId, 0, clickOffset);

          // IME selection should match
          final imeOffset =
              env.inputService.getImeState(doc.id).value.selection.baseOffset;
          expect(imeOffset, clickOffset,
              reason: 'IME offset should be $clickOffset after click');

          // Document cursor flat offset should match
          final cursor = (doc.selection.value as SingleCursorSelectionState)
              .cursorPos as CursorPositionInTextBlock;
          final block = doc.getBlockById(blockId) as TextBlock;
          final flat =
              block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);
          expect(flat, clickOffset,
              reason:
                  'Document cursor flat offset should be $clickOffset after click');
        }
      },
    );
  });
}
