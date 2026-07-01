// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/view/widgets/editor/compute_block_selection_info.dart';
import 'package:noetec/view/widgets/editor/text_block_render_widget.dart';

class BlockEditorWidget extends StatefulWidget {
  const BlockEditorWidget({super.key, required this.block, required this.page});

  final TextBlockEntity block;
  final PageEntity page;

  @override
  State<BlockEditorWidget> createState() => _BlockEditorWidgetState();
}

class _BlockEditorWidgetState extends State<BlockEditorWidget> {
  @override
  void initState() {
    super.initState();
    widget.page.selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant BlockEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) {
      oldWidget.page.selection.removeListener(_onSelectionChanged);
      widget.page.selection.addListener(_onSelectionChanged);
    }
  }

  void _onSelectionChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    widget.page.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionInfo = computeBlockSelectionInfo(
      blockId: widget.block.id,
      state: widget.page.selection.value,
      flatBlockIds: widget.page.flatBlockIds,
      selectedBlockIds: {},
    );

    return TextBlockRenderWidget(
      key: Key(widget.block.id),
      block: widget.block,
      selectionInfo: selectionInfo,
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      textStyle: DefaultTextStyle.of(context).style,
    );
  }
}
