// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/handlers/clipboard_input_handler.dart';
import 'package:noetec/UserInputSystem/handlers/ime_input_handler.dart';

/// Handles hardware keyboard events: modifier key tracking, hotkeys, printable
/// character input, and special keys (Backspace, Delete, Enter, Arrow keys).
class KeyboardInputHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final UserActionService _actionService;
  late final ImeInputHandler _ime;
  late final ClipboardInputHandler _clipboard;

  // Modifier keys state.
  bool _ctrlPressed = false;
  bool _shiftPressed = false;
  bool _altPressed = false;
  bool _metaPressed = false;

  bool get ctrlPressed => _ctrlPressed;
  bool get shiftPressed => _shiftPressed;
  bool get altPressed => _altPressed;
  bool get metaPressed => _metaPressed;

  void init(
    OpenedDocumentsManager documentsManager,
    UserActionService actionService,
    ImeInputHandler ime,
    ClipboardInputHandler clipboard,
  ) {
    _documentsManager = documentsManager;
    _actionService = actionService;
    _ime = ime;
    _clipboard = clipboard;
  }

  // ---------------------------------------------------------------------------
  // Hardware key events
  // ---------------------------------------------------------------------------

  void handleKeyEvent(String documentId, KeyDownEvent event) {
    _updateModifierKeys(event);
    _handleKey(documentId, event);
  }

  void handleKeyRepeat(String documentId, KeyRepeatEvent event) {
    _handleKey(documentId, event);
  }

  /// Should be called on [KeyUpEvent] to release modifier keys.
  void handleKeyUp(KeyUpEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      _ctrlPressed = false;
    } else if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      _shiftPressed = false;
    } else if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      _altPressed = false;
    } else if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      _metaPressed = false;
    }
  }

  void _handleKey(String documentId, KeyEvent event) {
    final key = event.logicalKey;

    // Hotkeys: Ctrl/Cmd + key.
    if (_ctrlPressed || _metaPressed) {
      if (key == LogicalKeyboardKey.keyA) {
        _clipboard.handleSelectAll(documentId);
        return;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _clipboard.handleCopy(documentId);
        return;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _clipboard.handleCut(documentId);
        return;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _clipboard.handlePaste(documentId);
        return;
      }
    }

    // Printable characters — only when no Ctrl/Meta modifier (to avoid
    // intercepting hotkeys like Ctrl+C, Ctrl+V, etc.).
    // character field is only present on KeyDownEvent and KeyRepeatEvent.
    if (!_ctrlPressed && !_metaPressed) {
      final String? character;
      if (event is KeyDownEvent) {
        character = event.character;
      } else if (event is KeyRepeatEvent) {
        character = event.character;
      } else {
        character = null;
      }
      if (character != null &&
          character.isNotEmpty &&
          !_isControlCharacter(character)) {
        _handleHardwareCharacterInput(documentId, character);
        return;
      }
    }

    // Special keys.
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
      if (_shiftPressed) {
        _handleExtendSelection(documentId, CursorMoveDirection.left);
      } else {
        _handleMoveCursor(documentId, CursorMoveDirection.left);
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_shiftPressed) {
        _handleExtendSelection(documentId, CursorMoveDirection.right);
      } else {
        _handleMoveCursor(documentId, CursorMoveDirection.right);
      }
      return;
    }
  }

  void _handleHardwareCharacterInput(String documentId, String character) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // If range selection is active, delete it first, then insert at the new cursor.
    if (selection is RangeSelectionState) {
      _actionService.handleAction(DeleteSelection(documentId: documentId));
    }

    // After potential deletion, re-read selection (now should be collapsed).
    final currentSelection = document.selection.value;
    if (currentSelection is! SingleCursorSelectionState) return;

    final cursor = currentSelection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _actionService.handleAction(
      InsertText(
        documentId: documentId,
        blockId: cursor.blockId,
        flatOffset: flatOffset,
        text: character,
      ),
    );

    // Sync IME state from the (now-mutated) document model.
    _ime.syncImeState(documentId, document);
  }

  void _handleBackspace(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // If range selection is active, just delete the selection (no extra char deletion).
    if (selection is RangeSelectionState) {
      _actionService.handleAction(DeleteSelection(documentId: documentId));
      _ime.syncImeState(documentId, document);
      return;
    }

    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _actionService.handleAction(
      DeleteTextBack(
        documentId: documentId,
        blockId: cursor.blockId,
        flatOffset: flatOffset,
      ),
    );

    _ime.syncImeState(documentId, document);
  }

  void _handleDelete(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // If range selection is active, just delete the selection.
    if (selection is RangeSelectionState) {
      _actionService.handleAction(DeleteSelection(documentId: documentId));
      _ime.syncImeState(documentId, document);
      return;
    }

    if (selection is! SingleCursorSelectionState) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _actionService.handleAction(
      DeleteTextForward(
        documentId: documentId,
        blockId: cursor.blockId,
        flatOffset: flatOffset,
      ),
    );

    _ime.syncImeState(documentId, document);
  }

  void _handleEnter(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // If range selection is active, delete it first, then split.
    if (selection is RangeSelectionState) {
      _actionService.handleAction(DeleteSelection(documentId: documentId));
    }

    final currentSelection = document.selection.value;
    if (currentSelection is! SingleCursorSelectionState) return;

    final cursor = currentSelection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = document.getBlockById(cursor.blockId);
    if (block is! TextBlock) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _actionService.handleAction(
      SplitTextBlock(
        documentId: documentId,
        blockId: cursor.blockId,
        splitFlatOffset: flatOffset,
      ),
    );

    // After split, cursor is on the new block — recompute IME state.
    _ime.syncImeState(documentId, document);
  }

  void _handleExtendSelection(
    String documentId,
    CursorMoveDirection direction,
  ) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    _actionService.handleAction(
      ExtendSelection(documentId: documentId, direction: direction),
    );

    _ime.syncImeState(documentId, document);
  }

  void _handleMoveCursor(String documentId, CursorMoveDirection direction) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    _actionService.handleAction(
      MoveCursor(documentId: documentId, direction: direction),
    );

    _ime.syncImeState(documentId, document);
  }

  void _updateModifierKeys(KeyDownEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      _ctrlPressed = true;
    } else if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      _shiftPressed = true;
    } else if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      _altPressed = true;
    } else if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      _metaPressed = true;
    }
  }

  /// Returns `true` for ASCII control characters (0x00-0x1F, 0x7F)
  /// that should NOT be treated as printable text input.
  static bool _isControlCharacter(String char) {
    if (char.isEmpty) return true;
    final code = char.codeUnitAt(0);
    return code < 0x20 || code == 0x7F;
  }
}
