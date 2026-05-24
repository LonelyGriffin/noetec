// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';
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
  ///
  /// {@macro flutter.widgets.ProxyWidget.child}
  final Widget child;

  /// Optional external focus node.
  ///
  /// If not provided, an internal focus node is created.
  final FocusNode? focusNode;

  @override
  State<UserRawTextInputWidget> createState() => _UserRawTextInputWidgetState();
}

class _UserRawTextInputWidgetState extends State<UserRawTextInputWidget>
    implements TextInputClient {
  late final FocusNode _focusNode;
  TextInputConnection? _textInputConnection;

  UserRawTextInputService get _inputService => di<UserRawTextInputService>();

  ValueNotifier<TextEditingValue> get _currentValue =>
      di<UserRawTextInputService>().getInputValue(widget.id)!;

  DocumentModel? get _document =>
      di<OpenedDocumentsManager>().getDocument(widget.id);

  @override
  void initState() {
    super.initState();
    // Ensure the buffer exists — DocumentEditorWidget registers it first, but
    // guard here in case the widget is used standalone.
    _inputService.registerInputIfNotExist(widget.id);

    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    _currentValue.addListener(_onCurrentValueChanged);

    // Subscribe to selection changes so the IME buffer stays in sync when the
    // user clicks a different block (or the caret moves programmatically).
    _document?.selection.addListener(_onDocumentSelectionChanged);
  }

  @override
  void dispose() {
    _closeInputConnectionIfNeeded();
    _focusNode.removeListener(_onFocusChange);
    _currentValue.removeListener(_onCurrentValueChanged);
    _document?.selection.removeListener(_onDocumentSelectionChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Focus
  // ---------------------------------------------------------------------------

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Sync buffer from the document before opening the IME connection so the
      // IME starts with the correct text / cursor for the active block.
      _inputService.syncBufferFromDocument(widget.id);
      _openInputConnection();
    } else {
      _closeInputConnectionIfNeeded();
    }
  }

  // ---------------------------------------------------------------------------
  // Selection changes (e.g. user clicked a different block)
  // ---------------------------------------------------------------------------

  void _onDocumentSelectionChanged() {
    // Re-sync the buffer whenever the active block changes so the IME always
    // reflects the text of the currently focused block.
    _inputService.syncBufferFromDocument(widget.id);
  }

  // ---------------------------------------------------------------------------
  // IME buffer → IME connection
  // ---------------------------------------------------------------------------

  void _onCurrentValueChanged() {
    // Do not echo back to the IME when the value change originated from the
    // IME itself — that would reset autocomplete suggestions.
    if (_inputService.isApplyingIMEUpdate) return;
    if (_textInputConnection != null && _textInputConnection!.attached) {
      _textInputConnection!.setEditingState(_currentValue.value);
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
          viewId: view.viewId,
        ),
      );
      _textInputConnection!.setEditingState(_currentValue.value);
      _textInputConnection!.show();
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_textInputConnection != null && _textInputConnection!.attached) {
      _textInputConnection!.close();
      _textInputConnection = null;
    }
  }

  // ---------------------------------------------------------------------------
  // TextInputClient
  // ---------------------------------------------------------------------------

  @override
  TextEditingValue get currentTextEditingValue => _currentValue.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _inputService.handleRawTextInputValueUpdate(widget.id, value);
  }

  @override
  void performAction(TextInputAction action) {
    // TextInputAction.newline is mapped to Enter — handled by hardware key
    // event. On mobile the IME may fire this instead.
    if (action == TextInputAction.newline) {
      _inputService.handleRawTextInputKeyEvent(
        widget.id,
        // Synthesise a logical Enter key-down event.
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

  // ---------------------------------------------------------------------------
  // Hardware keyboard
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    return _inputService.handleRawTextInputKeyEvent(widget.id, event);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
