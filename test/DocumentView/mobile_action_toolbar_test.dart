// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentView/mobile_action_toolbar.dart';
import 'package:noetec/InputModeService/input_mode_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:watch_it/watch_it.dart';

import '../helpers/test_document_factory.dart';
import '../helpers/test_environment.dart';

/// Registers services in the DI container for widget tests and returns the
/// [TestEnvironment].
TestEnvironment _registerDI() {
  final env = createTestEnvironment();
  final inputModeService = InputModeService();

  // Reset DI container (safe for tests).
  if (di.isRegistered<OpenedDocumentsManager>()) {
    di.unregister<OpenedDocumentsManager>();
  }
  if (di.isRegistered<InputModeService>()) di.unregister<InputModeService>();
  if (di.isRegistered(instance: env.inputService)) {
    di.unregister(instance: env.inputService);
  }
  if (di.isRegistered(instance: env.actionService)) {
    di.unregister(instance: env.actionService);
  }

  di.registerSingleton<OpenedDocumentsManager>(env.documentsManager);
  di.registerSingleton<InputModeService>(inputModeService);
  di.registerSingleton(env.inputService);
  di.registerSingleton(env.actionService);

  return env;
}

void _tearDownDI() {
  di.reset();
}

/// Pumps a [MobileActionToolbar] wrapped in a minimal Material widget tree.
Future<void> _pumpToolbar(
  WidgetTester tester, {
  required String documentId,
  required FocusNode focusNode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            // A simple focusable widget to give focus to the focus node.
            Focus(
              focusNode: focusNode,
              child: const SizedBox(width: 100, height: 100),
            ),
            MobileActionToolbar(documentId: documentId, focusNode: focusNode),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late TestEnvironment env;
  late FocusNode focusNode;

  setUp(() {
    env = _registerDI();
    focusNode = FocusNode();
  });

  tearDown(() {
    focusNode.dispose();
    _tearDownDI();
  });

  group('MobileActionToolbar', () {
    testWidgets('hidden in mouse mode', (tester) async {
      final (doc, _) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // Default mode is mouse.
      await _pumpToolbar(tester, documentId: doc.id, focusNode: focusNode);
      focusNode.requestFocus();
      await tester.pump();

      // Toolbar should be hidden (SizedBox.shrink renders as 0x0).
      expect(
        find.byType(MobileActionToolbar),
        findsOneWidget,
        reason: 'widget exists in tree',
      );
      // No toolbar buttons should be visible.
      expect(find.text('V'), findsNothing);
    });

    testWidgets('shows only V (Paste) in touch mode without selection', (
      tester,
    ) async {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      // Switch to touch mode.
      di<InputModeService>().mode.value = InputMode.touch;

      // Place cursor (single cursor, no range).
      env.inputService.handleTextClick(doc.id, blockId, 0, 2);

      await _pumpToolbar(tester, documentId: doc.id, focusNode: focusNode);
      focusNode.requestFocus();
      await tester.pump();

      // No range → no A, C, X.  Only V (Paste) is visible.
      expect(find.text('V'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.text('C'), findsNothing);
      expect(find.text('X'), findsNothing);
    });

    testWidgets('shows A, C, X, V in touch mode with range selection', (
      tester,
    ) async {
      final (doc, blockId) = createSingleSegmentDocument(text: 'Hello World');
      env.documentsManager.openDocument(doc);

      di<InputModeService>().mode.value = InputMode.touch;

      // Create a range selection.
      env.actionService.handleAction(
        SetRangeSelection(
          documentId: doc.id,
          anchorBlockId: blockId,
          anchorSegmentIndex: 0,
          anchorOffset: 0,
          extentBlockId: blockId,
          extentSegmentIndex: 0,
          extentOffset: 5,
        ),
      );

      await _pumpToolbar(tester, documentId: doc.id, focusNode: focusNode);
      focusNode.requestFocus();
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
    });

    testWidgets('hidden when editor does not have focus', (tester) async {
      final (doc, _) = createSingleSegmentDocument(text: 'Hello');
      env.documentsManager.openDocument(doc);

      di<InputModeService>().mode.value = InputMode.touch;

      await _pumpToolbar(tester, documentId: doc.id, focusNode: focusNode);
      // Do NOT request focus.
      await tester.pump();

      expect(find.text('V'), findsNothing);
    });
  });
}
