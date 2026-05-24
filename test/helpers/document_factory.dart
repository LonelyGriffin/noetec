// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

/// Creates a [TextBlock] with a single [TextSegment] containing [text],
/// placed at offset 0 in the given [document].
TextBlock makeTextBlock({
  required DocumentModel document,
  required String text,
  String? id,
  int insertAt = 0,
}) {
  final block = TextBlock(
    id: id ?? 'block-${document.rootBlocks.value.length}',
    documentId: document.id,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: [TextSegment(text: text)]),
  );
  document.addBlock(block, insertAt);
  return block;
}

/// Creates a [TextBlock] with an explicit list of [segments].
TextBlock makeTextBlockWithSegments({
  required DocumentModel document,
  required List<TextSegment> segments,
  String? id,
  int insertAt = 0,
}) {
  final block = TextBlock(
    id: id ?? 'block-${document.rootBlocks.value.length}',
    documentId: document.id,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: segments),
  );
  document.addBlock(block, insertAt);
  return block;
}

/// Creates a fresh [DocumentModel] with [id] and optionally registers it in
/// [manager].
DocumentModel makeDocument({
  String id = 'doc1',
  OpenedDocumentsManager? manager,
}) {
  final doc = DocumentModel(id: id);
  manager?.openDocument(doc);
  return doc;
}

/// Places a collapsed cursor at [segmentIndex]/[offset] inside [block] in
/// [document].
void setCursor(
  DocumentModel document,
  TextBlock block, {
  int segmentIndex = 0,
  int offset = 0,
}) {
  final cursor = TextSelectionCursorState(
    blockId: block.id,
    segmentIndex: segmentIndex,
    offset: offset,
  );
  document.selection.value = TextSelectionState(from: cursor, to: cursor);
}
