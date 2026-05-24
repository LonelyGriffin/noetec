// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

class UserActionService {
  final OpenedDocumentsManager _documentsManager;

  UserActionService(this._documentsManager);

  void handleAction(UserAction action) {
    _logAction(action);
    _processAction(action);
  }

  void _logAction(UserAction action) {
    final json = action.toJson();
    debugPrint('[UserAction] ${jsonEncode(json)}');
  }

  void _processAction(UserAction action) {
    switch (action) {
      case ClickOnTextBlock():
        _handleClickOnTextBlock(action);
      case ChangeTextSection():
        _handleChangeTextSection(action);
      case SplitTextBlock():
        _handleSplitTextBlock(action);
    }
  }

  void _handleClickOnTextBlock(ClickOnTextBlock action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final cursor = TextSelectionCursorState(
      blockId: action.blockId,
      segmentIndex: action.segmentIndex,
      offset: action.offset,
    );
    document.selection.value = TextSelectionState(from: cursor, to: cursor);
  }

  void _handleChangeTextSection(ChangeTextSection action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    // Replace segments atomically — single notification via transaction.
    block.segments.startTransAction();
    block.segments.clear();
    block.segments.addAll(action.newSegments);
    block.segments.endTransAction();

    // Update cursor position.
    final cursor = TextSelectionCursorState(
      blockId: action.blockId,
      segmentIndex: action.newSegmentIndex,
      offset: action.newOffset,
    );
    document.selection.value = TextSelectionState(from: cursor, to: cursor);
  }

  void _handleSplitTextBlock(SplitTextBlock action) {
    final document = _documentsManager.getDocument(action.documentId);
    if (document == null) return;

    final block = document.getBlockById(action.blockId);
    if (block is! TextBlock) return;

    final currentIndex = document.getBlockIndex(action.blockId);
    if (currentIndex == -1) return;

    final splitOffset = action.splitFlatOffset.clamp(
      0,
      block.flatText.length,
    );

    // Split segments at splitOffset, preserving formatting.
    final (beforeSegs, afterSegs) = _splitSegmentsAt(
      block.segments.value,
      splitOffset,
    );

    // Update the current block with the "before" part.
    final newBeforeSegs =
        beforeSegs.isEmpty ? [TextSegment(text: '')] : beforeSegs;
    block.segments.startTransAction();
    block.segments.clear();
    block.segments.addAll(newBeforeSegs);
    block.segments.endTransAction();

    // Create a new block for the "after" part.
    final newBlock = TextBlock(
      id: _uuid.v4(),
      documentId: action.documentId,
      parent: ValueNotifier(null),
      segments: ListNotifier(
        data: afterSegs.isEmpty ? [TextSegment(text: '')] : afterSegs,
      ),
    );
    document.addBlock(newBlock, currentIndex + 1);

    // Move cursor to the start of the new block.
    final cursor = TextSelectionCursorState(
      blockId: newBlock.id,
      segmentIndex: 0,
      offset: 0,
    );
    document.selection.value = TextSelectionState(from: cursor, to: cursor);
  }

  /// Splits [segments] at [flatOffset], returning two lists of segments.
  ///
  /// Formatting is preserved: if the split falls in the middle of a segment,
  /// that segment is duplicated into two with the same type and format, each
  /// carrying its respective portion of the text.
  (List<TextSegment> before, List<TextSegment> after) _splitSegmentsAt(
    List<TextSegment> segments,
    int flatOffset,
  ) {
    final before = <TextSegment>[];
    final after = <TextSegment>[];
    int remaining = flatOffset;

    for (final seg in segments) {
      final len = seg.text.length;

      if (remaining <= 0) {
        // Entirely in "after".
        after.add(seg);
      } else if (remaining >= len) {
        // Entirely in "before".
        before.add(seg);
        remaining -= len;
      } else {
        // Split falls inside this segment.
        final beforeText = seg.text.substring(0, remaining);
        final afterText = seg.text.substring(remaining);
        remaining = 0;

        before.add(_copySegmentWithText(seg, beforeText));
        after.add(_copySegmentWithText(seg, afterText));
      }
    }

    return (before, after);
  }

  /// Returns a copy of [seg] with [newText], preserving its concrete type and
  /// formatting attributes.
  TextSegment _copySegmentWithText(TextSegment seg, String newText) {
    if (seg is FormattedSegment) {
      return FormattedSegment(text: newText, format: seg.format);
    }
    if (seg is LinkSegment) {
      return LinkSegment(text: newText, url: seg.url);
    }
    return TextSegment(text: newText);
  }
}
