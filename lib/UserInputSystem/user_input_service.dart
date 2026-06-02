// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/handlers/clipboard_input_handler.dart';
import 'package:noetec/UserInputSystem/handlers/ime_input_handler.dart';
import 'package:noetec/UserInputSystem/handlers/keyboard_input_handler.dart';
import 'package:noetec/UserInputSystem/handlers/pointer_input_handler.dart';

/// Single gateway for all raw user input (IME deltas, pointer events, key events).
///
/// Acts as a thin facade that delegates each concern to a dedicated handler:
/// - [ImeInputHandler]       — IME text deltas and per-document [TextEditingValue]
/// - [PointerInputHandler]   — click and drag selection
/// - [KeyboardInputHandler]  — hardware key events and modifier key state
/// - [ClipboardInputHandler] — copy, cut, paste, and select-all
class UserInputService {
  final ImeInputHandler _ime = ImeInputHandler();
  final PointerInputHandler _pointer = PointerInputHandler();
  final ClipboardInputHandler _clipboard = ClipboardInputHandler();
  final KeyboardInputHandler _keyboard = KeyboardInputHandler();

  UserInputService({
    required OpenedDocumentsManager documentsManager,
    required UserActionService actionService,
  }) {
    _ime.init(documentsManager, actionService);
    _clipboard.init(documentsManager, actionService, _ime);
    _pointer.init(documentsManager, actionService, _ime);
    _keyboard.init(documentsManager, actionService, _ime, _clipboard);
  }

  // ---------------------------------------------------------------------------
  // IME state
  // ---------------------------------------------------------------------------

  /// Called when the platform IME must be told about a new [TextEditingValue]
  /// that originated from a non-IME event (click, keyboard navigation, etc.).
  ///
  /// The widget layer sets this to push the value via
  /// [TextInputConnection.setEditingState].
  VoidCallback? get onPlatformImeUpdateNeeded => _ime.onPlatformImeUpdateNeeded;

  set onPlatformImeUpdateNeeded(VoidCallback? cb) =>
      _ime.onPlatformImeUpdateNeeded = cb;

  /// Returns the IME state notifier for [documentId].
  /// Creates one with empty value if it doesn't exist yet.
  ValueNotifier<TextEditingValue> getImeState(String documentId) =>
      _ime.getImeState(documentId);

  // ---------------------------------------------------------------------------
  // Modifier keys (read-only view into KeyboardInputHandler)
  // ---------------------------------------------------------------------------

  bool get ctrlPressed => _keyboard.ctrlPressed;
  bool get shiftPressed => _keyboard.shiftPressed;
  bool get altPressed => _keyboard.altPressed;
  bool get metaPressed => _keyboard.metaPressed;

  // ---------------------------------------------------------------------------
  // IME text deltas
  // ---------------------------------------------------------------------------

  void handleTextDeltas(String documentId, List<TextEditingDelta> deltas) =>
      _ime.handleTextDeltas(documentId, deltas);

  // ---------------------------------------------------------------------------
  // Pointer events
  // ---------------------------------------------------------------------------

  void handleTextClick(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    if (_keyboard.shiftPressed) {
      _pointer.handleShiftClick(documentId, blockId, segmentIndex, offset);
    } else {
      _pointer.handleTextClick(documentId, blockId, segmentIndex, offset);
    }
  }

  void handleDragStart(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) => _pointer.handleDragStart(documentId, blockId, segmentIndex, offset);

  void handleDragUpdate(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) => _pointer.handleDragUpdate(documentId, blockId, segmentIndex, offset);

  void handleDragEnd(String documentId) => _pointer.handleDragEnd(documentId);

  void swapSelectionAnchors(String documentId) =>
      _pointer.swapSelectionAnchors(documentId);

  // ---------------------------------------------------------------------------
  // Hardware key events
  // ---------------------------------------------------------------------------

  void handleKeyEvent(String documentId, KeyDownEvent event) =>
      _keyboard.handleKeyEvent(documentId, event);

  void handleKeyRepeat(String documentId, KeyRepeatEvent event) =>
      _keyboard.handleKeyRepeat(documentId, event);

  void handleKeyUp(KeyUpEvent event) => _keyboard.handleKeyUp(event);

  // ---------------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------------

  void handleSelectAll(String documentId) =>
      _clipboard.handleSelectAll(documentId);

  void handleCopy(String documentId) => _clipboard.handleCopy(documentId);

  void handleCut(String documentId) => _clipboard.handleCut(documentId);

  void handlePaste(String documentId) => _clipboard.handlePaste(documentId);
}
