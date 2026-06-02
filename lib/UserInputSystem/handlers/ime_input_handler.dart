// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

/// Handles IME text delta events and maintains per-document [TextEditingValue]
/// state.
///
/// Also owns [onPlatformImeUpdateNeeded] — the callback that tells the widget
/// layer to push a new [TextEditingValue] to the platform text input connection.
/// All other input handlers call [syncImeState] to trigger this callback after
/// non-IME events.
class ImeInputHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final UserActionService _actionService;

  // IME state per document.
  final Map<String, ValueNotifier<TextEditingValue>> _imeStates = {};

  /// Called when the platform IME must be told about a new [TextEditingValue]
  /// that originated from a non-IME event (click, keyboard navigation, etc.).
  ///
  /// The widget layer sets this to push the value via
  /// [TextInputConnection.setEditingState].
  VoidCallback? onPlatformImeUpdateNeeded;

  void init(
    OpenedDocumentsManager documentsManager,
    UserActionService actionService,
  ) {
    _documentsManager = documentsManager;
    _actionService = actionService;
  }

  /// Returns the IME state notifier for [documentId].
  /// Creates one with empty value if it doesn't exist yet.
  ValueNotifier<TextEditingValue> getImeState(String documentId) {
    return _imeStates.putIfAbsent(
      documentId,
      () => ValueNotifier(TextEditingValue.empty),
    );
  }

  /// Syncs the IME state from the document model and notifies the platform.
  ///
  /// Called by other handlers after any non-IME mutation that changes the
  /// cursor or text (clicks, key events, drag, clipboard).
  void syncImeState(String documentId, DocumentModel document) {
    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  // ---------------------------------------------------------------------------
  // IME text deltas
  // ---------------------------------------------------------------------------

  void handleTextDeltas(String documentId, List<TextEditingDelta> deltas) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    for (final delta in deltas) {
      switch (delta) {
        case TextEditingDeltaInsertion():
          _handleInsertion(documentId, document, delta);
        case TextEditingDeltaReplacement():
          _handleReplacement(documentId, document, delta);
        case TextEditingDeltaNonTextUpdate():
          _handleNonTextUpdate(documentId, document, delta);
        default:
          break;
      }
    }
  }

  void _handleInsertion(
    String documentId,
    DocumentModel document,
    TextEditingDeltaInsertion delta,
  ) {
    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final imeState = getImeState(documentId);

    _actionService.handleAction(
      InsertText(
        documentId: documentId,
        blockId: cursor.blockId,
        flatOffset: delta.insertionOffset,
        text: delta.textInserted,
      ),
    );

    imeState.value = delta.apply(imeState.value);
  }

  void _handleReplacement(
    String documentId,
    DocumentModel document,
    TextEditingDeltaReplacement delta,
  ) {
    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    _actionService.handleAction(
      ReplaceText(
        documentId: documentId,
        blockId: cursor.blockId,
        flatStart: delta.replacedRange.start,
        flatEnd: delta.replacedRange.end,
        replacementText: delta.replacementText,
      ),
    );

    getImeState(documentId).value = document.computeTextEditingValue();
  }

  void _handleNonTextUpdate(
    String documentId,
    DocumentModel document,
    TextEditingDeltaNonTextUpdate delta,
  ) {
    // Only handle collapsed selections (single cursor).
    // Range selections from IME are ignored for now.
    if (!delta.selection.isCollapsed) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    _actionService.handleAction(
      SetCursorPosition(
        documentId: documentId,
        blockId: cursor.blockId,
        flatOffset: delta.selection.baseOffset,
      ),
    );

    getImeState(documentId).value = document.computeTextEditingValue();
  }
}
