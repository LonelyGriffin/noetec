// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentView/document_editor_block_widget.dart';
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
    );
  }
}
