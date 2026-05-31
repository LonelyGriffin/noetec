// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
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

    _actionService.handleAction(InsertText(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: delta.insertionOffset,
      text: delta.textInserted,
    ));

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

    _actionService.handleAction(ReplaceText(
      documentId: documentId,
      blockId: cursor.blockId,
      flatStart: delta.replacedRange.start,
      flatEnd: delta.replacedRange.end,
      replacementText: delta.replacementText,
    ));

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

    _actionService.handleAction(SetCursorPosition(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: delta.selection.baseOffset,
    ));

    getImeState(documentId).value = document.computeTextEditingValue();
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

    // Printable characters — only when no Ctrl/Meta modifier (to avoid
    // intercepting hotkeys like Ctrl+C, Ctrl+V, etc.).
    if (!_ctrlPressed && !_metaPressed) {
      final character = event.character;
      if (character != null &&
          character.isNotEmpty &&
          !_isControlCharacter(character)) {
        _handleHardwareCharacterInput(documentId, character);
        return;
      }
    }

    // Special keys.
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      _handleBackspace(documentId);
      return;
    }
    if (key == LogicalKeyboardKey.delete) {
      _handleDelete(documentId);
      return;
    }
    if (key == LogicalKeyboardKey.enter) {
      _handleEnter(documentId);
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _handleMoveCursor(documentId, CursorMoveDirection.left);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _handleMoveCursor(documentId, CursorMoveDirection.right);
      return;
    }
  }

  void _handleHardwareCharacterInput(String documentId, String character) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset =
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);

    _actionService.handleAction(InsertText(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: flatOffset,
      text: character,
    ));

    // Sync IME state from the (now-mutated) document model.
    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  void _handleBackspace(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset =
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);

    _actionService.handleAction(DeleteTextBack(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: flatOffset,
    ));

    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  void _handleDelete(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset =
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);

    _actionService.handleAction(DeleteTextForward(
      documentId: documentId,
      blockId: cursor.blockId,
      flatOffset: flatOffset,
    ));

    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  void _handleEnter(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset =
        block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset);

    _actionService.handleAction(SplitTextBlock(
      documentId: documentId,
      blockId: cursor.blockId,
      splitFlatOffset: flatOffset,
    ));

    // After split, cursor is on the new block — recompute IME state.
    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  void _handleMoveCursor(String documentId, CursorMoveDirection direction) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    _actionService.handleAction(MoveCursor(
      documentId: documentId,
      direction: direction,
    ));

    getImeState(documentId).value = document.computeTextEditingValue();
    onPlatformImeUpdateNeeded?.call();
  }

  /// Returns `true` for ASCII control characters (0x00-0x1F, 0x7F)
  /// that should NOT be treated as printable text input.
  static bool _isControlCharacter(String char) {
    if (char.isEmpty) return true;
    final code = char.codeUnitAt(0);
    return code < 0x20 || code == 0x7F;
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
