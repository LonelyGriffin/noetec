// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/document_editor_block_widget.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';
import 'package:noetec/InputModeService/input_mode_service.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_widget.dart';
import 'package:watch_it/watch_it.dart';

class DocumentEditorWidget extends WatchingStatefulWidget {
  const DocumentEditorWidget({
    super.key,
    required this.documentId,
    this.focusNode,
  });

  final String documentId;

  /// Optional external [FocusNode].  When provided, the widget does not
  /// create its own node.  This allows sharing the focus state with other
  /// widgets such as [MobileActionToolbar].
  final FocusNode? focusNode;

  @override
  State<DocumentEditorWidget> createState() => _DocumentEditorWidgetState();
}

class _DocumentEditorWidgetState extends State<DocumentEditorWidget> {
  late final FocusNode _focusNode;

  /// Active drag anchor point (mouse mode), or `null` if no drag is in
  /// progress.
  (String blockId, int segmentIndex, int offset)? _dragAnchor;

  /// Whether the user is currently dragging a cursor handle after a
  /// long-press in touch mode.
  bool _isDraggingCursor = false;

  UserInputService get _inputService => di<UserInputService>();
  UserActionService get _actionService => di<UserActionService>();
  InputModeService get _inputModeService => di<InputModeService>();

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final documentModel =
        di<OpenedDocumentsManager>().openedDocuments[widget.documentId];

    if (documentModel == null) {
      return const SizedBox.shrink();
    }

    final rootBlocks = watch(documentModel.rootBlocks);

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: UserRawTextInputWidget(
        id: widget.documentId,
        focusNode: _focusNode,
        // Listener is passive — it does not participate in the gesture arena.
        // Used for two purposes:
        //   1. Detect pointer kind to update InputModeService on every
        //      pointer-down.
        //   2. Handle mouse click/drag selection (mouse mode only).
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          // GestureDetector participates in the gesture arena and resolves
          // the conflict between touch long-press and ListView scroll
          // automatically.  Callbacks are guarded by InputMode check so they
          // only fire in touch mode.
          child: GestureDetector(
            onTapUp: _onTouchTapUp,
            onLongPressStart: _onTouchLongPressStart,
            onLongPressMoveUpdate: _onTouchLongPressMoveUpdate,
            onLongPressEnd: _onTouchLongPressEnd,
            child: ListView.builder(
              itemCount: rootBlocks.length,
              itemBuilder: (context, index) {
                final block = rootBlocks[index];
                return DocumentEditorBlockWidget(
                  block: block,
                  documentId: widget.documentId,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Passive Listener callbacks (mode detection + mouse handling)
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    _inputModeService.updateFromPointerEvent(event);

    // Only handle mouse events here; touch is handled by GestureDetector.
    if (_inputModeService.mode.value != InputMode.mouse) return;
    if (event.buttons & kPrimaryButton == 0) return;

    _focusNode.requestFocus();

    final hit = _hitTestTextBlock(event.position);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;

    if (_inputService.shiftPressed) {
      _inputService.handleTextClick(
        widget.documentId,
        blockId,
        segmentIndex,
        offset,
      );
    } else {
      _inputService.handleDragStart(
        widget.documentId,
        blockId,
        segmentIndex,
        offset,
      );
    }
    _dragAnchor = hit;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_inputModeService.mode.value != InputMode.mouse) return;
    if (_dragAnchor == null) return;

    final hit = _hitTestTextBlock(event.position);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;
    _inputService.handleDragUpdate(
      widget.documentId,
      blockId,
      segmentIndex,
      offset,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_inputModeService.mode.value != InputMode.mouse) return;
    if (_dragAnchor == null) return;
    _dragAnchor = null;

    _inputService.handleDragEnd(widget.documentId);
  }

  // ---------------------------------------------------------------------------
  // GestureDetector callbacks (touch handling)
  // ---------------------------------------------------------------------------

  /// Touch tap: place cursor at the tapped position.
  void _onTouchTapUp(TapUpDetails details) {
    if (_inputModeService.mode.value != InputMode.touch) return;

    _focusNode.requestFocus();

    final hit = _hitTestTextBlock(details.globalPosition);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;
    _inputService.handleTextClick(
      widget.documentId,
      blockId,
      segmentIndex,
      offset,
    );
  }

  /// Touch long-press start: either grab an existing cursor/handle for
  /// dragging, or select the word under the finger.
  void _onTouchLongPressStart(LongPressStartDetails details) {
    if (_inputModeService.mode.value != InputMode.touch) return;

    _focusNode.requestFocus();

    final hit = _hitTestTextBlock(details.globalPosition);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;
    final document = di<OpenedDocumentsManager>().getDocument(
      widget.documentId,
    );
    if (document == null) return;

    final selection = document.selection.value;

    // Check if the user long-pressed on the anchor position.
    if (_isOnCursor(selection, blockId, segmentIndex, offset, isAnchor: true)) {
      // Swap anchor/extent so the grabbed end becomes the movable extent.
      _inputService.swapSelectionAnchors(widget.documentId);
      _isDraggingCursor = true;
      return;
    }

    // Check if the user long-pressed on the extent position.
    if (_isOnCursor(
      selection,
      blockId,
      segmentIndex,
      offset,
      isAnchor: false,
    )) {
      _isDraggingCursor = true;
      return;
    }

    // Not on any cursor — select the word under the finger.
    _actionService.handleAction(
      SelectWord(
        documentId: widget.documentId,
        blockId: blockId,
        segmentIndex: segmentIndex,
        offset: offset,
      ),
    );
    _isDraggingCursor = false;
  }

  /// Touch long-press move: drag the extent cursor if a handle was grabbed.
  void _onTouchLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_inputModeService.mode.value != InputMode.touch) return;
    if (!_isDraggingCursor) return;

    final hit = _hitTestTextBlock(details.globalPosition);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;
    _inputService.handleDragUpdate(
      widget.documentId,
      blockId,
      segmentIndex,
      offset,
    );
  }

  /// Touch long-press end: finalize cursor drag.
  void _onTouchLongPressEnd(LongPressEndDetails details) {
    if (_inputModeService.mode.value != InputMode.touch) return;
    if (_isDraggingCursor) {
      _inputService.handleDragEnd(widget.documentId);
      _isDraggingCursor = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if the given text position matches the [isAnchor]
  /// (anchor or extent) end of the current selection.
  bool _isOnCursor(
    SelectionState selection,
    String blockId,
    int segmentIndex,
    int offset, {
    required bool isAnchor,
  }) {
    CursorPositionInTextBlock? cursor;

    if (selection is SingleCursorSelectionState) {
      // For a collapsed cursor, both "anchor" and "extent" are the same.
      final c = selection.cursorPos;
      if (c is CursorPositionInTextBlock) cursor = c;
    } else if (selection is RangeSelectionState) {
      final c = isAnchor ? selection.anchor : selection.extent;
      if (c is CursorPositionInTextBlock) cursor = c;
    }

    if (cursor == null) return false;
    return cursor.blockId == blockId &&
        cursor.segmentIndex == segmentIndex &&
        cursor.offset == offset;
  }

  /// Performs a hit test at the given global position and returns
  /// (blockId, segmentIndex, offset) if a TextBlock was hit.
  (String, int, int)? _hitTestTextBlock(Offset globalPosition) {
    final result = HitTestResult();
    final viewId = View.of(context).viewId;
    WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);

    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderTextBlockContent) {
        final localOffset = target.globalToLocal(globalPosition);
        final point = target.getPositionForLocalOffset(localOffset);
        if (point != null) {
          return (target.block.id, point.segmentIndex, point.offset);
        }
      }
    }
    return null;
  }
}
