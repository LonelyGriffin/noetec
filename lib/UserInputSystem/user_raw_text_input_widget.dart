// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:watch_it/watch_it.dart';

class UserRawTextInputWidget extends WatchingStatefulWidget {
  const UserRawTextInputWidget({
    super.key,
    required this.id,
    required this.child,
    this.focusNode,
  });

  /// The document ID this widget manages input for.
  final String id;

  /// The child widget.
  final Widget child;

  /// Optional external focus node.
  ///
  /// If not provided, an internal focus node is created.
  final FocusNode? focusNode;

  @override
  State<UserRawTextInputWidget> createState() => _UserRawTextInputWidgetState();
}

class _UserRawTextInputWidgetState extends State<UserRawTextInputWidget> with DeltaTextInputClient {
  late final FocusNode _focusNode;
  TextInputConnection? _textInputConnection;

  UserInputService get _inputService => di<UserInputService>();

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    _inputService.onPlatformImeUpdateNeeded = _syncPlatformIme;
  }

  @override
  void dispose() {
    // Clear the callback only if we are still the registered owner.
    if (_inputService.onPlatformImeUpdateNeeded == _syncPlatformIme) {
      _inputService.onPlatformImeUpdateNeeded = null;
    }
    _closeInputConnectionIfNeeded();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  TextEditingValue get currentTextEditingValue =>
      _inputService.getImeState(widget.id).value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    assert(false, 'updateEditingValue should not be called when enableDeltaModel is true');
  }

  @override
  bool onFocusReceived() {
    return false;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    _inputService.handleTextDeltas(widget.id, textEditingDeltas);
  }

  @override
  void performAction(TextInputAction action) {
    // TextInputAction.newline is mapped to Enter -- on mobile the IME may
    // fire this instead of a hardware key event.
    if (action == TextInputAction.newline) {
      _inputService.handleKeyEvent(
        widget.id,
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _textInputConnection = null;
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }

  /// Pushes the current in-memory IME state to the platform text input
  /// connection. Called by [UserInputService] after non-IME events (clicks,
  /// keyboard navigation) that change the cursor position.
  void _syncPlatformIme() {
    if (_textInputConnection != null && _textInputConnection!.attached) {
      _textInputConnection!.setEditingState(
        _inputService.getImeState(widget.id).value,
      );
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _openInputConnection();
    } else {
      _closeInputConnectionIfNeeded();
    }
  }

  void _openInputConnection() {
    if (_textInputConnection == null || !_textInputConnection!.attached) {
      final view = View.of(context);
      _textInputConnection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          enableSuggestions: true,
          autocorrect: true,
          inputAction: TextInputAction.newline,
          enableDeltaModel: true,
          viewId: view.viewId,
        ),
      );
      final value = _inputService.getImeState(widget.id).value;
      _textInputConnection!.setEditingState(value);
      _textInputConnection!.show();
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_textInputConnection != null && _textInputConnection!.attached) {
      _textInputConnection!.close();
      _textInputConnection = null;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _inputService.handleKeyEvent(widget.id, event);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      _inputService.handleKeyRepeat(widget.id, event);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _inputService.handleKeyUp(event);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
