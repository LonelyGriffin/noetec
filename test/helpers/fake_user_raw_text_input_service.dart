// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';

/// A test double for [UserRawTextInputService] used in widget tests.
///
/// Allows widget tests to verify that the widget correctly delegates to the
/// service, without running the full document mutation logic.
class FakeUserRawTextInputService extends UserRawTextInputService {
  FakeUserRawTextInputService({required super.documentsManager})
      : super(actionService: _NoOpFakeActionService());

  // Recorded calls — inspectable by tests.
  final List<String> syncBufferCalls = [];
  final List<({String documentId, TextEditingValue value})> valueUpdateCalls =
      [];
  final List<({String documentId, KeyEvent event})> keyEventCalls = [];

  @override
  void syncBufferFromDocument(String documentId) {
    syncBufferCalls.add(documentId);
    super.syncBufferFromDocument(documentId);
  }

  @override
  void handleRawTextInputValueUpdate(String documentId, TextEditingValue value) {
    valueUpdateCalls.add((documentId: documentId, value: value));
    super.handleRawTextInputValueUpdate(documentId, value);
  }

  @override
  KeyEventResult handleRawTextInputKeyEvent(
    String documentId,
    KeyEvent event,
  ) {
    keyEventCalls.add((documentId: documentId, event: event));
    return super.handleRawTextInputKeyEvent(documentId, event);
  }

  void reset() {
    syncBufferCalls.clear();
    valueUpdateCalls.clear();
    keyEventCalls.clear();
  }
}

class _NoOpFakeActionService extends UserActionService {
  _NoOpFakeActionService() : super(OpenedDocumentsManager());

  @override
  void handleAction(UserAction action) {}
}
