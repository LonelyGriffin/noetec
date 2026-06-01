// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';

/// Creates a [DocumentModel] with a single [TextBlock] containing one plain
/// text segment.
///
/// Returns `(document, blockId)`.
(DocumentModel, String) createSingleSegmentDocument({
  String documentId = 'test-doc',
  String blockId = 'block-1',
  String text = 'Hello, World!',
}) {
  final doc = DocumentModel(id: documentId);
  final block = TextBlock(
    id: blockId,
    documentId: documentId,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: [TextSegment(text: text)]),
  );
  doc.addBlock(block, 0);
  return (doc, blockId);
}

/// Creates a [DocumentModel] with a single [TextBlock] containing multiple
/// segments of different types.
///
/// Default layout:
///   segment 0: "Hello " (plain, length 6)
///   segment 1: "bold"   (bold,  length 4)
///   segment 2: " world" (plain, length 6)
///
/// Total text: "Hello bold world" (length 16)
///
/// Returns `(document, blockId)`.
(DocumentModel, String) createMultiSegmentDocument({
  String documentId = 'test-doc',
  String blockId = 'block-1',
  List<TextSegment>? segments,
}) {
  segments ??= [
    const TextSegment(text: 'Hello '),
    const FormattedSegment(text: 'bold', format: TextFormat.bold),
    const TextSegment(text: ' world'),
  ];

  final doc = DocumentModel(id: documentId);
  final block = TextBlock(
    id: blockId,
    documentId: documentId,
    parent: ValueNotifier(null),
    segments: ListNotifier(data: segments),
  );
  doc.addBlock(block, 0);
  return (doc, blockId);
}

/// Creates a [DocumentModel] with multiple [TextBlock]s.
///
/// Returns `(document, List<blockId>)`.
(DocumentModel, List<String>) createMultiBlockDocument({
  String documentId = 'test-doc',
  List<(String blockId, String text)>? blocks,
}) {
  blocks ??= [
    ('block-1', 'First paragraph'),
    ('block-2', 'Second paragraph'),
    ('block-3', 'Third paragraph'),
  ];

  final doc = DocumentModel(id: documentId);
  final blockIds = <String>[];

  for (var i = 0; i < blocks.length; i++) {
    final (blockId, text) = blocks[i];
    final block = TextBlock(
      id: blockId,
      documentId: documentId,
      parent: ValueNotifier(null),
      segments: ListNotifier(data: [TextSegment(text: text)]),
    );
    doc.addBlock(block, i);
    blockIds.add(blockId);
  }

  return (doc, blockIds);
}

/// Helper to read the full text of a [TextBlock] by its ID from a document.
String blockText(DocumentModel doc, String blockId) {
  final block = doc.getBlockById(blockId) as TextBlock;
  return block.computeAllSegmentsText();
}

/// Helper to read all segment texts of a [TextBlock].
List<String> blockSegmentTexts(DocumentModel doc, String blockId) {
  final block = doc.getBlockById(blockId) as TextBlock;
  return block.segments.value.map((s) => s.text).toList();
}
