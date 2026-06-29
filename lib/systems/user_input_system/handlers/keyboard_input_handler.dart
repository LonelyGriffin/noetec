// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/user_input_system/handlers/clipboard_input_handler.dart';
import 'package:noetec/systems/user_input_system/handlers/ime_input_handler.dart';

class KeyboardInputHandler {
  late final PageSystem _pageSystem;
  late final ImeInputHandler _ime;
  late final ClipboardInputHandler _clipboard;

  bool _ctrlPressed = false;
  bool _shiftPressed = false;
  bool _altPressed = false;
  bool _metaPressed = false;

  bool get ctrlPressed => _ctrlPressed;
  bool get shiftPressed => _shiftPressed;
  bool get altPressed => _altPressed;
  bool get metaPressed => _metaPressed;

  void init(
    PageSystem pageSystem,
    ImeInputHandler ime,
    ClipboardInputHandler clipboard,
  ) {
    _pageSystem = pageSystem;
    _ime = ime;
    _clipboard = clipboard;
  }

  void handleKeyEvent(String pageId, KeyDownEvent event) {
    _updateModifierKeys(event);
    _handleKey(pageId, event);
  }

  void handleKeyRepeat(String pageId, KeyRepeatEvent event) {
    _handleKey(pageId, event);
  }

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

  void _handleKey(String pageId, KeyEvent event) {
    final key = event.logicalKey;

    if (_ctrlPressed || _metaPressed) {
      if (key == LogicalKeyboardKey.keyS) {
        _handleSave(pageId);
        return;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _clipboard.handleSelectAll();
        return;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _clipboard.handleCopy();
        return;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _clipboard.handleCut();
        return;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _clipboard.handlePaste();
        return;
      }
    }

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
        _handleHardwareCharacterInput(character);
        return;
      }
    }

    if (key == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return;
    }
    if (key == LogicalKeyboardKey.delete) {
      _handleDelete();
      return;
    }
    if (key == LogicalKeyboardKey.enter) {
      _handleEnter();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_shiftPressed) {
        _pageSystem.selection.extendSelection(CursorMoveDirection.left);
      } else {
        _pageSystem.selection.moveCursor(CursorMoveDirection.left);
      }
      _ime.syncImeState(pageId);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_shiftPressed) {
        _pageSystem.selection.extendSelection(CursorMoveDirection.right);
      } else {
        _pageSystem.selection.moveCursor(CursorMoveDirection.right);
      }
      _ime.syncImeState(pageId);
      return;
    }
  }

  void _handleSave(String pageId) {
    _pageSystem.savePage(pageId);
  }

  void _handleHardwareCharacterInput(String character) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    if (selection is RangeSelectionEntity) {
      _pageSystem.editing.deleteSelection();
    }

    final currentSelection = page.selection.value;
    if (currentSelection is! SingleCursorSelectionEntity) return;

    final cursor = currentSelection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _pageSystem.editing.insertText(flatOffset, character);

    _ime.syncImeState(_pageSystem.activePageId.value!);
  }

  void _handleBackspace() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    if (selection is RangeSelectionEntity) {
      _pageSystem.editing.deleteSelection();
      _ime.syncImeState(_pageSystem.activePageId.value!);
      return;
    }

    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _pageSystem.editing.deleteTextBack(flatOffset);

    _ime.syncImeState(_pageSystem.activePageId.value!);
  }

  void _handleDelete() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    if (selection is RangeSelectionEntity) {
      _pageSystem.editing.deleteSelection();
      _ime.syncImeState(_pageSystem.activePageId.value!);
      return;
    }

    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _pageSystem.editing.deleteTextForward(flatOffset);

    _ime.syncImeState(_pageSystem.activePageId.value!);
  }

  void _handleEnter() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final selection = page.selection.value;

    if (selection is RangeSelectionEntity) {
      _pageSystem.editing.deleteSelection();
    }

    final currentSelection = page.selection.value;
    if (currentSelection is! SingleCursorSelectionEntity) return;

    final cursor = currentSelection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _pageSystem.editing.splitBlock(flatOffset);

    _ime.syncImeState(_pageSystem.activePageId.value!);
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

  static bool _isControlCharacter(String char) {
    if (char.isEmpty) return true;
    final code = char.codeUnitAt(0);
    return code < 0x20 || code == 0x7F;
  }
}
