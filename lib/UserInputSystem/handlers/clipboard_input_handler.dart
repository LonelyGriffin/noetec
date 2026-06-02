// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/handlers/ime_input_handler.dart';

/// Handles clipboard operations: copy, cut, paste, and select-all.
class ClipboardInputHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final UserActionService _actionService;
  late final ImeInputHandler _ime;

  void init(
    OpenedDocumentsManager documentsManager,
    UserActionService actionService,
    ImeInputHandler ime,
  ) {
    _documentsManager = documentsManager;
    _actionService = actionService;
    _ime = ime;
  }

  void handleSelectAll(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    _actionService.handleAction(SelectAll(documentId: documentId));

    _ime.syncImeState(documentId, document);
  }

  void handleCopy(String documentId) {
    final markdown = _actionService.extractSelectedMarkdown(documentId);
    if (markdown == null) return;

    Clipboard.setData(ClipboardData(text: markdown));
  }

  void handleCut(String documentId) {
    final markdown = _actionService.extractSelectedMarkdown(documentId);
    if (markdown == null) return;

    Clipboard.setData(ClipboardData(text: markdown));

    _actionService.handleAction(DeleteSelection(documentId: documentId));

    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      _ime.syncImeState(documentId, document);
    }
  }

  void handlePaste(String documentId) async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.isEmpty) return;

    _actionService.handleAction(
      Paste(documentId: documentId, clipboardContent: data.text!),
    );

    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      _ime.syncImeState(documentId, document);
    }
  }
}
