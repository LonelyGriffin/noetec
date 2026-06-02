// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/handlers/text_editing_handler.dart';
import 'package:noetec/UserActionSystem/handlers/cursor_handler.dart';
import 'package:noetec/UserActionSystem/handlers/selection_handler.dart';
import 'package:noetec/UserActionSystem/handlers/clipboard_handler.dart';

/// Main service for processing user actions on documents.
///
/// This service dispatches each user action to the appropriate handler,
/// which modifies the document model and updates the selection state.
/// It also provides public utility methods for extracting selected content.
class UserActionService {
  final TextEditingHandler _textEditingHandler = TextEditingHandler();
  final CursorHandler _cursorHandler = CursorHandler();
  final SelectionHandler _selectionHandler = SelectionHandler();
  final ClipboardHandler _clipboardHandler = ClipboardHandler();

  /// Creates a new UserActionService with the given dependencies.
  UserActionService(
    OpenedDocumentsManager documentsManager,
    IdService idService,
  ) {
    _textEditingHandler.init(documentsManager, idService);
    _cursorHandler.init(documentsManager);
    _selectionHandler.init(documentsManager, _cursorHandler);
    _clipboardHandler.init(documentsManager, idService, _selectionHandler);
  }

  /// Processes a user action by dispatching it to the appropriate handler.
  void handleAction(UserAction action) {
    switch (action) {
      case InsertText():
        _textEditingHandler.handleInsertText(action);
      case ClickOnTextBlock():
        _cursorHandler.handleClickOnTextBlock(action);
      case SplitTextBlock():
        _textEditingHandler.handleSplitTextBlock(action);
      case DeleteTextBack():
        _textEditingHandler.handleDeleteTextBack(action);
      case DeleteTextForward():
        _textEditingHandler.handleDeleteTextForward(action);
      case MoveCursor():
        _cursorHandler.handleMoveCursor(action);
      case ReplaceText():
        _textEditingHandler.handleReplaceText(action);
      case SetCursorPosition():
        _cursorHandler.handleSetCursorPosition(action);
      case ExtendSelection():
        _selectionHandler.handleExtendSelection(action);
      case SetRangeSelection():
        _selectionHandler.handleSetRangeSelection(action);
      case SelectAll():
        _selectionHandler.handleSelectAll(action);
      case DeleteSelection():
        _selectionHandler.handleDeleteSelection(action);
      case Paste():
        _clipboardHandler.handlePaste(action);
      case SelectWord():
        _selectionHandler.handleSelectWord(action);
    }
  }

  /// Extracts the currently selected content as a markdown string.
  ///
  /// Returns `null` if there is no range selection.
  /// This is a read-only operation — it does not modify the document.
  String? extractSelectedMarkdown(String documentId) =>
      _clipboardHandler.extractSelectedMarkdown(documentId);
}
