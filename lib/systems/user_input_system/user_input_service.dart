// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/persistence_system/persistence_system.dart';
import 'package:noetec/systems/user_input_system/handlers/clipboard_input_handler.dart';
import 'package:noetec/systems/user_input_system/handlers/ime_input_handler.dart';
import 'package:noetec/systems/user_input_system/handlers/keyboard_input_handler.dart';
import 'package:noetec/systems/user_input_system/handlers/pointer_input_handler.dart';

class UserInputService {
  final ImeInputHandler _ime = ImeInputHandler();
  final PointerInputHandler _pointer = PointerInputHandler();
  final ClipboardInputHandler _clipboard = ClipboardInputHandler();
  final KeyboardInputHandler _keyboard = KeyboardInputHandler();

  UserInputService(PageSystem pageSystem, PersistenceSystem persistence) {
    _ime.init(pageSystem);
    _clipboard.init(pageSystem, _ime);
    _pointer.init(pageSystem, _ime);
    _keyboard.init(pageSystem, persistence, _ime, _clipboard);
  }

  VoidCallback? get onPlatformImeUpdateNeeded => _ime.onPlatformImeUpdateNeeded;

  set onPlatformImeUpdateNeeded(VoidCallback? cb) =>
      _ime.onPlatformImeUpdateNeeded = cb;

  ValueNotifier<TextEditingValue> getImeState(String pageId) =>
      _ime.getImeState(pageId);

  bool get ctrlPressed => _keyboard.ctrlPressed;
  bool get shiftPressed => _keyboard.shiftPressed;
  bool get altPressed => _keyboard.altPressed;
  bool get metaPressed => _keyboard.metaPressed;

  void handleTextDeltas(String pageId, List<TextEditingDelta> deltas) =>
      _ime.handleTextDeltas(pageId, deltas);

  void handleTextClick(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    if (_keyboard.shiftPressed) {
      _pointer.handleShiftClick(pageId, blockId, segmentIndex, offset);
    } else {
      _pointer.handleTextClick(pageId, blockId, segmentIndex, offset);
    }
  }

  void handleDragStart(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) => _pointer.handleDragStart(pageId, blockId, segmentIndex, offset);

  void handleDragUpdate(
    String pageId,
    String blockId,
    int segmentIndex,
    int offset,
  ) => _pointer.handleDragUpdate(pageId, blockId, segmentIndex, offset);

  void handleDragEnd(String pageId) => _pointer.handleDragEnd(pageId);

  void swapSelectionAnchors() => _pointer.swapSelectionAnchors();

  void handleKeyEvent(String pageId, KeyDownEvent event) =>
      _keyboard.handleKeyEvent(pageId, event);

  void handleKeyRepeat(String pageId, KeyRepeatEvent event) =>
      _keyboard.handleKeyRepeat(pageId, event);

  void handleKeyUp(KeyUpEvent event) => _keyboard.handleKeyUp(event);

  void handleSelectAll() => _clipboard.handleSelectAll();

  void handleCopy() => _clipboard.handleCopy();

  void handleCut() => _clipboard.handleCut();

  void handlePaste() => _clipboard.handlePaste();
}
