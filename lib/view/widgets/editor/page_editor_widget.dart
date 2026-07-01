// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/user_input_system/user_input_service.dart';
import 'package:noetec/systems/user_input_system/user_raw_text_input_widget.dart';
import 'package:noetec/view/widgets/editor/block_editor_widget.dart';
import 'package:noetec/view/widgets/editor/text_block_render_widget.dart';
import 'package:watch_it/watch_it.dart';

class PageEditorWidget extends StatefulWidget {
  const PageEditorWidget({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageEditorWidget> createState() => _PageEditorWidgetState();
}

class _PageEditorWidgetState extends State<PageEditorWidget> {
  late final FocusNode _focusNode;

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
    final pageSystem = di<PageSystem>();
    final page = pageSystem.openPages[widget.pageId];

    if (page == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: UserRawTextInputWidget(
        pageId: widget.pageId,
        focusNode: _focusNode,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: page.rootBlocks.length,
            itemBuilder: (context, index) {
              final block = page.rootBlocks[index] as TextBlockEntity;
              return BlockEditorWidget(block: block, page: page);
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
      _inputService.handleTextClick(
        widget.pageId,
        blockId,
        segmentIndex,
        offset,
      );
    } else {
      _inputService.handleDragStart(
        widget.pageId,
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
      widget.pageId,
      blockId,
      segmentIndex,
      offset,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_dragAnchor == null) return;
    _dragAnchor = null;

    _inputService.handleDragEnd(widget.pageId);
  }

  (String, int, int)? _hitTestTextBlock(Offset globalPosition) {
    final result = HitTestResult();
    final viewId = View.of(context).viewId;
    WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);

    for (final entry in result.path) {
      final target = entry.target;
      if (target is TextBlockRenderBox) {
        final localOffset = target.globalToLocal(globalPosition);
        final point = target.getPositionForLocalOffset(localOffset);
        if (point != null) {
          return (target.blockId, point.segmentIndex, point.offset);
        }
      }
    }
    return null;
  }
}
