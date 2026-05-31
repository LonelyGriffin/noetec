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

/// Single gateway for all raw user input (IME deltas, pointer events, key events).
///
/// Responsibilities:
/// 1. Translate raw platform events into domain [UserAction]s
/// 2. Dispatch actions to [UserActionService]
/// 3. Maintain IME state ([TextEditingValue]) per document
/// 4. Track modifier key state for hotkey detection
class UserInputService {
  final OpenedDocumentsManager _documentsManager;
  final UserActionService _actionService;

  // Modifier keys state
  bool _ctrlPressed = false;
  bool _shiftPressed = false;
  bool _altPressed = false;
  bool _metaPressed = false;

  bool get ctrlPressed => _ctrlPressed;
  bool get shiftPressed => _shiftPressed;
  bool get altPressed => _altPressed;
  bool get metaPressed => _metaPressed;

  // IME state per document
  final Map<String, ValueNotifier<TextEditingValue>> _imeStates = {};

  /// Called when the platform IME must be told about a new [TextEditingValue]
  /// that originated from a non-IME event (click, keyboard navigation, etc.).
  ///
  /// The widget layer sets this to push the value via
  /// [TextInputConnection.setEditingState].
  /// The argument is the document ID whose IME state changed.
  VoidCallback? onPlatformImeUpdateNeeded;

  UserInputService({
    required OpenedDocumentsManager documentsManager,
    required UserActionService actionService,
  })  : _documentsManager = documentsManager,
        _actionService = actionService;

  /// Returns the IME state notifier for [documentId].
  /// Creates one with empty value if it doesn't exist yet.
  ValueNotifier<TextEditingValue> getImeState(String documentId) {
    return _imeStates.putIfAbsent(
      documentId,
      () => ValueNotifier(TextEditingValue.empty),
    );
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

    _actionService.handleAction(InsertText(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: delta.insertionOffset,
      text: delta.textInserted,
    ));

    imeState.value = delta.apply(imeState.value);
  }

  // ---------------------------------------------------------------------------
  // Pointer events
  // ---------------------------------------------------------------------------

  void handleTextClick(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    _actionService.handleAction(ClickOnTextBlock(
      documentId: documentId,
      blockId: blockId,
      segmentIndex: segmentIndex,
      offset: offset,
    ));

    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      getImeState(documentId).value = document.computeTextEditingValue();
      onPlatformImeUpdateNeeded?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // Hardware key events
  // ---------------------------------------------------------------------------

  void handleKeyEvent(String documentId, KeyDownEvent event) {
    _updateModifierKeys(event);
    // TODO: translate key events into actions (Enter, Backspace, Delete, hotkeys)
  }

  void _updateModifierKeys(KeyDownEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
      _ctrlPressed = true;
    } else if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      _shiftPressed = true;
    } else if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
      _altPressed = true;
    } else if (key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight) {
      _metaPressed = true;
    }
  }

  /// Should be called on KeyUpEvent to release modifier keys.
  void handleKeyUp(KeyUpEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
      _ctrlPressed = false;
    } else if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      _shiftPressed = false;
    } else if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
      _altPressed = false;
    } else if (key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight) {
      _metaPressed = false;
    }
  }
}
