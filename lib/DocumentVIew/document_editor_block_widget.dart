// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:watch_it/watch_it.dart';

class DocumentEditorBlockWidget extends StatefulWidget {
  const DocumentEditorBlockWidget({
    super.key,
    required this.block,
    required this.documentId,
  });

  final Block block;
  final String documentId;

  @override
  State<DocumentEditorBlockWidget> createState() =>
      _DocumentEditorBlockWidgetState();
}

class _DocumentEditorBlockWidgetState extends State<DocumentEditorBlockWidget> {
  DocumentModel get _model => di<OpenedDocumentsManager>().getDocument(widget.documentId)!;

  @override
  void initState() {
    super.initState();
    _model.selection.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _model.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.block is! TextBlock) return const SizedBox.shrink();

    final textBlock = widget.block as TextBlock;
    final selectionInfo = _computeBlockSelectionInfo(
      textBlock.id,
      _model.selection.value,
    );

    return TextBlockWidget(
      key: Key(textBlock.id),
      block: textBlock,
      selectionInfo: selectionInfo,
      onTextClick: (blockId, segmentIndex, offset) {
        di<UserInputService>().handleTextClick(
          widget.documentId,
          blockId,
          segmentIndex,
          offset,
        );
      },
    );
  }

  /// Computes what role this specific block plays in the current selection.
  BlockSelectionInfo _computeBlockSelectionInfo(
    String blockId,
    SelectionState state,
  ) {
    if (state is NoSelectionState) {
      return BlockNotSelected();
    }

    if (state is SingleCursorSelectionState) {
      final cursorPos = state.cursorPos;

      if (cursorPos is! CursorPositionInTextBlock) {
        return BlockNotSelected();
      }

      return cursorPos.blockId == blockId ? BlockWithCursor(cursorPos: cursorPos) : BlockNotSelected();
    }

    if (state is RangeSelectionState) {
      final fromCursorPos = state.from;
      final toCursorPos = state.to;

      if (
        fromCursorPos is CursorPositionInTextBlock &&
        toCursorPos is CursorPositionInTextBlock &&
        fromCursorPos.blockId == toCursorPos.blockId &&
        fromCursorPos.blockId == blockId
      ) {
        return BlockWithRange(fromCursorPos: fromCursorPos, toCursorPos: toCursorPos);
      }

      if (fromCursorPos is CursorPositionInTextBlock && fromCursorPos.blockId == blockId) {
        return BlockWithFromCursor(cursorPos: fromCursorPos);
      }

      if (toCursorPos is CursorPositionInTextBlock && toCursorPos.blockId == blockId) {
        return BlockWithToCursor(cursorPos: toCursorPos);
      }

      return BlockNotSelected();
    }

    if (_model.selectedBlockIds.value.contains(blockId)) {
      return BlockFullySelected();
    }

    return BlockNotSelected();
  }
}
