// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';

import '../helpers/document_factory.dart';
import '../helpers/fake_user_action_service.dart';

// ---------------------------------------------------------------------------
// Key event factories (top-level — getters are not allowed inside group())
// ---------------------------------------------------------------------------

KeyDownEvent makeBackspace() => KeyDownEvent(
      logicalKey: LogicalKeyboardKey.backspace,
      physicalKey: PhysicalKeyboardKey.backspace,
      timeStamp: Duration.zero,
    );

KeyDownEvent makeDeleteKey() => KeyDownEvent(
      logicalKey: LogicalKeyboardKey.delete,
      physicalKey: PhysicalKeyboardKey.delete,
      timeStamp: Duration.zero,
    );

void main() {
  late OpenedDocumentsManager manager;
  late FakeUserActionService actions;
  late UserRawTextInputService sut;
  late DocumentModel doc;

  /// Registers a document in the manager and opens an IME buffer for it.
  void setupDoc(DocumentModel d) {
    manager.openDocument(d);
    sut.registerInputIfNotExist(d.id);
  }

  setUp(() {
    manager = OpenedDocumentsManager();
    actions = FakeUserActionService();
    sut = UserRawTextInputService(
      documentsManager: manager,
      actionService: actions,
    );
    doc = makeDocument(id: 'doc1');
    setupDoc(doc);
  });

  // ---------------------------------------------------------------------------
  // syncBufferFromDocument
  // ---------------------------------------------------------------------------

  group('syncBufferFromDocument', () {
    test('sets buffer text and cursor from the active segment', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3);

      sut.syncBufferFromDocument('doc1');

      final buf = sut.getInputValue('doc1')!.value;
      expect(buf.text, equals('hello'));
      expect(buf.selection.baseOffset, equals(3));
    });

    test('uses correct segment when segmentIndex > 0', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'first'),
          TextSegment(text: 'second'),
        ],
      );
      setCursor(doc, block, segmentIndex: 1, offset: 2);

      sut.syncBufferFromDocument('doc1');

      final buf = sut.getInputValue('doc1')!.value;
      expect(buf.text, equals('second'));
      expect(buf.selection.baseOffset, equals(2));
    });

    test('clears buffer when selection is NoSelectionState', () {
      makeTextBlock(document: doc, text: 'hello', id: 'b1');
      doc.selection.value = NoSelectionState();

      sut.syncBufferFromDocument('doc1');

      expect(sut.getInputValue('doc1')!.value, equals(TextEditingValue.empty));
    });

    test('clears buffer when block is not a TextBlock', () {
      // Point the selection at a non-existent block id — getBlockById returns null.
      final cursor = TextSelectionCursorState(
        blockId: 'not-a-text-block',
        segmentIndex: 0,
        offset: 0,
      );
      doc.selection.value = TextSelectionState(from: cursor, to: cursor);

      sut.syncBufferFromDocument('doc1');

      expect(sut.getInputValue('doc1')!.value, equals(TextEditingValue.empty));
    });

    test('clears buffer when segments list is empty', () {
      final block = TextBlock(
        id: 'b1',
        documentId: 'doc1',
        parent: ValueNotifier(null),
        segments: ListNotifier(data: []),
      );
      doc.addBlock(block, 0);
      setCursor(doc, block);

      sut.syncBufferFromDocument('doc1');

      expect(sut.getInputValue('doc1')!.value, equals(TextEditingValue.empty));
    });

    test('clamps out-of-range segmentIndex without throwing', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      // Force a cursor with segmentIndex beyond the list.
      final cursor = TextSelectionCursorState(
        blockId: 'b1',
        segmentIndex: 99,
        offset: 0,
      );
      doc.selection.value = TextSelectionState(from: cursor, to: cursor);

      expect(() => sut.syncBufferFromDocument('doc1'), returnsNormally);

      final buf = sut.getInputValue('doc1')!.value;
      expect(buf.text, equals(block.segments.value.last.text));
    });

    test('clamps out-of-range offset without throwing', () {
      final block = makeTextBlock(document: doc, text: 'hi', id: 'b1');
      final cursor = TextSelectionCursorState(
        blockId: 'b1',
        segmentIndex: 0,
        offset: 999,
      );
      doc.selection.value = TextSelectionState(from: cursor, to: cursor);

      expect(() => sut.syncBufferFromDocument('doc1'), returnsNormally);

      final buf = sut.getInputValue('doc1')!.value;
      expect(buf.selection.baseOffset, equals(2)); // clamped to text.length
    });

    test('is a no-op for unknown documentId', () {
      expect(
        () => sut.syncBufferFromDocument('no-such-doc'),
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputValueUpdate
  // ---------------------------------------------------------------------------

  group('handleRawTextInputValueUpdate', () {
    test('dispatches ChangeTextSection when text changes', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 5);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputValueUpdate(
        'doc1',
        const TextEditingValue(
          text: 'hello!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );

      expect(actions.actions.length, equals(1));
      final action = actions.lastAction as ChangeTextSection;
      expect(action.documentId, equals('doc1'));
      expect(action.blockId, equals('b1'));
      expect(action.newSegments.first.text, equals('hello!'));
      expect(action.newOffset, equals(6));
    });

    test('does NOT dispatch action when only cursor moves (text unchanged)', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 0);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputValueUpdate(
        'doc1',
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(actions.actions, isEmpty);
    });

    test('updates the notifier value to the new TextEditingValue', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 5);
      sut.syncBufferFromDocument('doc1');

      const newValue = TextEditingValue(
        text: 'hello!',
        selection: TextSelection.collapsed(offset: 6),
      );
      sut.handleRawTextInputValueUpdate('doc1', newValue);

      expect(sut.getInputValue('doc1')!.value, equals(newValue));
    });

    test('isApplyingIMEUpdate is true during notifier write, false after', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 5);
      sut.syncBufferFromDocument('doc1');

      final observedDuringUpdate = <bool>[];
      sut.getInputValue('doc1')!.addListener(() {
        observedDuringUpdate.add(sut.isApplyingIMEUpdate);
      });

      sut.handleRawTextInputValueUpdate(
        'doc1',
        const TextEditingValue(
          text: 'hello!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );

      // During the listener fire, flag must be true.
      expect(observedDuringUpdate, contains(true));
      // After the call returns, flag must be false.
      expect(sut.isApplyingIMEUpdate, isFalse);
    });

    test('is a no-op for unknown documentId', () {
      expect(
        () => sut.handleRawTextInputValueUpdate(
          'no-such-doc',
          const TextEditingValue(text: 'x'),
        ),
        returnsNormally,
      );
      expect(actions.actions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputKeyEvent — ignored cases
  // ---------------------------------------------------------------------------

  group('handleRawTextInputKeyEvent — ignored events', () {
    test('KeyUpEvent is ignored', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 2);
      sut.syncBufferFromDocument('doc1');

      final result = sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      );

      expect(result, equals(KeyEventResult.ignored));
    });

    test('unregistered documentId returns ignored', () {
      final result = sut.handleRawTextInputKeyEvent(
        'unknown-doc',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );
      expect(result, equals(KeyEventResult.ignored));
    });

    test('arrow key returns ignored', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block);
      sut.syncBufferFromDocument('doc1');

      final result = sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      );
      expect(result, equals(KeyEventResult.ignored));
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputKeyEvent — Backspace
  // ---------------------------------------------------------------------------

  group('handleRawTextInputKeyEvent — Backspace', () {

    test('deletes character before cursor mid-segment', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3); // cursor after 'l'
      sut.syncBufferFromDocument('doc1');

      final result = sut.handleRawTextInputKeyEvent('doc1', makeBackspace());

      expect(result, equals(KeyEventResult.handled));
      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('helo'));
      expect(action.newOffset, equals(2));
    });

    test('deletes selected range when selection is non-collapsed', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 1);
      sut.syncBufferFromDocument('doc1');
      // Simulate a range selection [1,4).
      sut.getInputValue('doc1')!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );

      sut.handleRawTextInputKeyEvent('doc1', makeBackspace());

      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('ho'));
      expect(action.newOffset, equals(1));
    });

    test('at offset=0 with non-empty left segment crosses segment boundary', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'abc'),
          TextSegment(text: 'def'),
        ],
      );
      // Cursor at start of segment 1.
      setCursor(doc, block, segmentIndex: 1, offset: 0);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeBackspace());

      final action = actions.lastAction as ChangeTextSection;
      // 'c' deleted from 'abc' → 'ab'; cursor in seg 0 at offset 2.
      expect(action.newSegments[0].text, equals('ab'));
      expect(action.newSegmentIndex, equals(0));
      expect(action.newOffset, equals(2));
    });

    test('at offset=0 skips empty segments to the left', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'abc'),
          TextSegment(text: ''), // empty — should be skipped
          TextSegment(text: 'def'),
        ],
      );
      // Cursor at start of segment 2 ("def").
      setCursor(doc, block, segmentIndex: 2, offset: 0);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeBackspace());

      final action = actions.lastAction as ChangeTextSection;
      // Empty seg removed; 'c' deleted from 'abc' → 'ab'.
      expect(action.newSegments.length, equals(2));
      expect(action.newSegments[0].text, equals('ab'));
    });

    test('at offset=0 of first segment is a no-op (start of block)', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 0);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeBackspace());

      // No action dispatched — beginning of block, nothing to delete.
      expect(actions.actions, isEmpty);
    });

    test('KeyRepeatEvent for Backspace is also handled', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3);
      sut.syncBufferFromDocument('doc1');

      final result = sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyRepeatEvent(
          logicalKey: LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          timeStamp: Duration.zero,
        ),
      );

      expect(result, equals(KeyEventResult.handled));
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputKeyEvent — Delete (forward)
  // ---------------------------------------------------------------------------

  group('handleRawTextInputKeyEvent — Delete', () {

    test('deletes character after cursor mid-segment', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 2); // cursor before second 'l'
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeDeleteKey());

      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('helo'));
      expect(action.newOffset, equals(2)); // cursor stays
    });

    test('deletes selected range', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block);
      sut.syncBufferFromDocument('doc1');
      sut.getInputValue('doc1')!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );

      sut.handleRawTextInputKeyEvent('doc1', makeDeleteKey());

      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('hlo'));
    });

    test('at end of segment crosses into next segment', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'abc'),
          TextSegment(text: 'def'),
        ],
      );
      // Cursor at end of segment 0.
      setCursor(doc, block, segmentIndex: 0, offset: 3);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeDeleteKey());

      final action = actions.lastAction as ChangeTextSection;
      // 'd' deleted from 'def' → 'ef'
      expect(action.newSegments[1].text, equals('ef'));
      // Cursor stays in segment 0.
      expect(action.newSegmentIndex, equals(0));
      expect(action.newOffset, equals(3));
    });

    test('at end of segment skips empty segments to the right', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'abc'),
          TextSegment(text: ''), // empty
          TextSegment(text: 'def'),
        ],
      );
      setCursor(doc, block, segmentIndex: 0, offset: 3);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeDeleteKey());

      final action = actions.lastAction as ChangeTextSection;
      // Empty seg removed; 'd' deleted from 'def' → 'ef'; 2 segs remain.
      expect(action.newSegments.length, equals(2));
      expect(action.newSegments.last.text, equals('ef'));
    });

    test('at end of last segment is a no-op', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 5);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent('doc1', makeDeleteKey());

      expect(actions.actions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputKeyEvent — Enter
  // ---------------------------------------------------------------------------

  group('handleRawTextInputKeyEvent — Enter', () {
    test('dispatches SplitTextBlock with correct flatOffset', () {
      final block = makeTextBlockWithSegments(
        document: doc,
        id: 'b1',
        segments: [
          TextSegment(text: 'hello '),
          TextSegment(text: 'world'),
        ],
      );
      // Cursor in segment 1 at offset 3 → flat offset = 6 + 3 = 9
      setCursor(doc, block, segmentIndex: 1, offset: 3);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      final action = actions.lastAction as SplitTextBlock;
      expect(action.documentId, equals('doc1'));
      expect(action.blockId, equals('b1'));
      expect(action.splitFlatOffset, equals(9));
    });

    test('numpadEnter also dispatches SplitTextBlock', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 2);
      sut.syncBufferFromDocument('doc1');

      final result = sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.numpadEnter,
          physicalKey: PhysicalKeyboardKey.numpadEnter,
          timeStamp: Duration.zero,
        ),
      );

      expect(result, equals(KeyEventResult.handled));
      expect(actions.lastAction, isA<SplitTextBlock>());
    });
  });

  // ---------------------------------------------------------------------------
  // handleRawTextInputKeyEvent — printable character
  // ---------------------------------------------------------------------------

  group('handleRawTextInputKeyEvent — printable character', () {
    test('inserts character at cursor position', () {
      final block = makeTextBlock(document: doc, text: 'hllo', id: 'b1');
      setCursor(doc, block, offset: 1);
      sut.syncBufferFromDocument('doc1');

      sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyE,
          physicalKey: PhysicalKeyboardKey.keyE,
          character: 'e',
          timeStamp: Duration.zero,
        ),
      );

      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('hello'));
      expect(action.newOffset, equals(2));
    });

    test('replaces selected text with typed character', () {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 1);
      sut.syncBufferFromDocument('doc1');
      sut.getInputValue('doc1')!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );

      sut.handleRawTextInputKeyEvent(
        'doc1',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
        ),
      );

      final action = actions.lastAction as ChangeTextSection;
      expect(action.newSegments.first.text, equals('hao'));
    });
  });

  // ---------------------------------------------------------------------------
  // registerInputIfNotExist / unregisterInput
  // ---------------------------------------------------------------------------

  group('register / unregister', () {
    test('registerInputIfNotExist creates a notifier with empty value', () {
      final sut2 = UserRawTextInputService(
        documentsManager: manager,
        actionService: actions,
      );
      sut2.registerInputIfNotExist('new-doc');

      expect(sut2.getInputValue('new-doc'), isNotNull);
      expect(
          sut2.getInputValue('new-doc')!.value, equals(TextEditingValue.empty));
    });

    test('registerInputIfNotExist does not overwrite an existing notifier', () {
      const initial = TextEditingValue(
        text: 'kept',
        selection: TextSelection.collapsed(offset: 4),
      );
      sut.registerInputIfNotExist('doc1', initial);
      // Already registered in setUp — value should still be empty (or whatever
      // it was), not overwritten by initial.
      // The notifier from setUp is TextEditingValue.empty.
      expect(sut.getInputValue('doc1')!.value.text, isNot(equals('kept')));
    });

    test('unregisterInput removes the notifier', () {
      sut.unregisterInput('doc1');
      expect(sut.getInputValue('doc1'), isNull);
    });
  });
}
