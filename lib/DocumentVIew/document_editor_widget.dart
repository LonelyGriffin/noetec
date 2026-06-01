// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentView/document_editor_block_widget.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_widget.dart';
import 'package:watch_it/watch_it.dart';

class DocumentEditorWidget extends WatchingStatefulWidget {
  const DocumentEditorWidget({super.key, required this.documentId});

  final String documentId;

  @override
  State<DocumentEditorWidget> createState() => _DocumentEditorWidgetState();
}

class _DocumentEditorWidgetState extends State<DocumentEditorWidget> {
  late final FocusNode _focusNode;

  /// Active drag anchor point, or `null` if no drag is in progress.
  (String blockId, int segmentIndex, int offset)? _dragAnchor;

  UserInputService get _inputService => di<UserInputService>();

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
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
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kPrimaryButton == 0) return;

    _focusNode.requestFocus();

    final hit = _hitTestTextBlock(event.position);
    if (hit == null) return;

    final (blockId, segmentIndex, offset) = hit;

    if (_inputService.shiftPressed) {
      // Shift+Click: extend selection.
      _inputService.handleTextClick(
        widget.documentId,
        blockId,
        segmentIndex,
        offset,
      );
    } else {
      // Normal click: set anchor for potential drag.
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
    if (_dragAnchor == null) return;
    _dragAnchor = null;

    _inputService.handleDragEnd(widget.documentId);
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
