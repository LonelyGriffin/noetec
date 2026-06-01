// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentView/compute_block_selection_info.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';
import 'package:noetec/InputModeService/input_mode_service.dart';
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
  DocumentModel get _model =>
      di<OpenedDocumentsManager>().getDocument(widget.documentId)!;

  InputModeService get _inputModeService => di<InputModeService>();

  @override
  void initState() {
    super.initState();
    _model.selection.addListener(_onSelectionChanged);
    _inputModeService.mode.addListener(_onInputModeChanged);
  }

  void _onSelectionChanged() {
    setState(() {});
  }

  void _onInputModeChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _model.selection.removeListener(_onSelectionChanged);
    _inputModeService.mode.removeListener(_onInputModeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.block is! TextBlock) return const SizedBox.shrink();

    final textBlock = widget.block as TextBlock;
    final selectionInfo = computeBlockSelectionInfo(
      blockId: textBlock.id,
      state: _model.selection.value,
      flatBlockIds: _model.flatBlockIds,
      selectedBlockIds: _model.selectedBlockIds.value,
    );

    return TextBlockWidget(
      key: Key(textBlock.id),
      block: textBlock,
      selectionInfo: selectionInfo,
      isTouchMode: _inputModeService.mode.value == InputMode.touch,
    );
  }
}
