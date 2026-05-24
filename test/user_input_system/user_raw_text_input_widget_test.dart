// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_widget.dart';

import '../helpers/document_factory.dart';
import '../helpers/fake_user_action_service.dart';

// ---------------------------------------------------------------------------
// DI helpers
// ---------------------------------------------------------------------------

({
  OpenedDocumentsManager manager,
  FakeUserActionService actions,
  UserRawTextInputService inputService,
}) setUpDI() {
  final manager = OpenedDocumentsManager();
  final actions = FakeUserActionService();
  final inputService = UserRawTextInputService(
    documentsManager: manager,
    actionService: actions,
  );

  final di = GetIt.instance;
  di.registerSingleton<OpenedDocumentsManager>(manager);
  di.registerSingleton<UserActionService>(actions);
  di.registerSingleton<UserRawTextInputService>(inputService);

  return (manager: manager, actions: actions, inputService: inputService);
}

Future<void> tearDownDI() => GetIt.instance.reset();

// ---------------------------------------------------------------------------
// Widget pump helper
//
// Accepts an external FocusNode so tests can call requestFocus() without
// relying on tap() hit-testing (which fails in headless test environments).
// ---------------------------------------------------------------------------

Future<void> pumpInputWidget(
  WidgetTester tester,
  String docId,
  FocusNode focusNode,
) async {
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => UserRawTextInputWidget(
        id: docId,
        focusNode: focusNode,
        child: const SizedBox(width: 100, height: 40),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late OpenedDocumentsManager manager;
  late FakeUserActionService actions;
  late UserRawTextInputService inputService;
  late DocumentModel doc;

  const docId = 'doc1';

  setUp(() {
    final handles = setUpDI();
    manager = handles.manager;
    actions = handles.actions;
    inputService = handles.inputService;

    doc = makeDocument(id: docId, manager: manager);
    inputService.registerInputIfNotExist(docId);
  });

  tearDown(() async {
    await tearDownDI();
  });

  // ---------------------------------------------------------------------------
  // Focus lifecycle
  // ---------------------------------------------------------------------------

  group('Focus lifecycle', () {
    testWidgets('gaining focus opens IME connection', (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);

      focusNode.dispose();
    });

    testWidgets('IME receives correct initial editing state on focus',
        (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();

      final state = tester.testTextInput.editingState!;
      expect(state['text'], equals('hello'));
      expect(state['selectionBase'], equals(3));
      expect(state['selectionExtent'], equals(3));

      focusNode.dispose();
    });

    testWidgets('losing focus closes IME connection', (tester) async {
      makeTextBlock(document: doc, text: 'hello', id: 'b1');
      final inputFocusNode = FocusNode();
      final otherFocusNode = FocusNode();

      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Column(
            children: [
              UserRawTextInputWidget(
                id: docId,
                focusNode: inputFocusNode,
                child: const SizedBox(width: 100, height: 40),
              ),
              Focus(
                focusNode: otherFocusNode,
                child: const SizedBox(width: 100, height: 40),
              ),
            ],
          ),
        ),
      );

      inputFocusNode.requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      otherFocusNode.requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);

      inputFocusNode.dispose();
      otherFocusNode.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // IME → document
  // ---------------------------------------------------------------------------

  group('IME input → document', () {
    testWidgets('updateEditingValue triggers ChangeTextSection', (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 5);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();
      actions.reset();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      expect(actions.actions.whereType<ChangeTextSection>(), isNotEmpty);
      final action = actions.actions.whereType<ChangeTextSection>().last;
      expect(action.newSegments.first.text, equals('hello!'));

      focusNode.dispose();
    });

    testWidgets('TextInputAction.newline triggers SplitTextBlock',
        (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 2);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();
      actions.reset();

      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();

      expect(actions.actions.whereType<SplitTextBlock>(), isNotEmpty);

      focusNode.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Document → IME (echo-back prevention)
  // ---------------------------------------------------------------------------

  group('document → IME sync', () {
    testWidgets(
        'programmatic selection change updates IME via setEditingState',
        (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 0);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();

      // Move cursor programmatically — triggers _onDocumentSelectionChanged
      // → syncBufferFromDocument → notifier update → setEditingState.
      setCursor(doc, block, offset: 5);
      await tester.pump();

      final state = tester.testTextInput.editingState!;
      expect(state['selectionBase'], equals(5));
      expect(state['selectionExtent'], equals(5));

      focusNode.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Hardware keyboard via widget
  // ---------------------------------------------------------------------------

  group('hardware keyboard', () {
    testWidgets('Backspace key dispatches ChangeTextSection', (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 3);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();
      actions.reset();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(actions.actions.whereType<ChangeTextSection>(), isNotEmpty);

      focusNode.dispose();
    });

    testWidgets('Enter key dispatches SplitTextBlock', (tester) async {
      final block = makeTextBlock(document: doc, text: 'hello', id: 'b1');
      setCursor(doc, block, offset: 2);

      final focusNode = FocusNode();
      await pumpInputWidget(tester, docId, focusNode);

      focusNode.requestFocus();
      await tester.pump();
      actions.reset();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(actions.actions.whereType<SplitTextBlock>(), isNotEmpty);

      focusNode.dispose();
    });
  });
}
