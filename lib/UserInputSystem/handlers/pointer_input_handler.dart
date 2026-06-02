// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/handlers/ime_input_handler.dart';

/// Handles pointer events: single clicks, Shift+Click, drag selection, and
/// anchor swapping for mobile long-press drag.
class PointerInputHandler {
  late final OpenedDocumentsManager _documentsManager;
  late final UserActionService _actionService;
  late final ImeInputHandler _ime;

  void init(
    OpenedDocumentsManager documentsManager,
    UserActionService actionService,
    ImeInputHandler ime,
  ) {
    _documentsManager = documentsManager;
    _actionService = actionService;
    _ime = ime;
  }

  // ---------------------------------------------------------------------------
  // Pointer events
  // ---------------------------------------------------------------------------

  void handleTextClick(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    _actionService.handleAction(
      ClickOnTextBlock(
        documentId: documentId,
        blockId: blockId,
        segmentIndex: segmentIndex,
        offset: offset,
      ),
    );

    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      _ime.syncImeState(documentId, document);
    }
  }

  /// Variant used when Shift is held: extends selection from the current
  /// anchor to the clicked position.
  void handleShiftClick(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    _handleShiftClick(documentId, blockId, segmentIndex, offset);

    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      _ime.syncImeState(documentId, document);
    }
  }

  void _handleShiftClick(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    // Determine the anchor: current cursor or current anchor if range.
    CursorPositionInTextBlock anchor;
    if (selection is SingleCursorSelectionState) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
    } else if (selection is RangeSelectionState) {
      final a = selection.anchor;
      if (a is! CursorPositionInTextBlock) return;
      anchor = a;
    } else {
      return;
    }

    _actionService.handleAction(
      SetRangeSelection(
        documentId: documentId,
        anchorBlockId: anchor.blockId,
        anchorSegmentIndex: anchor.segmentIndex,
        anchorOffset: anchor.offset,
        extentBlockId: blockId,
        extentSegmentIndex: segmentIndex,
        extentOffset: offset,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drag selection
  // ---------------------------------------------------------------------------

  /// Called when a pointer-down begins a potential drag selection.
  void handleDragStart(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    // Set the anchor at the drag start position (collapsed cursor).
    _actionService.handleAction(
      ClickOnTextBlock(
        documentId: documentId,
        blockId: blockId,
        segmentIndex: segmentIndex,
        offset: offset,
      ),
    );
  }

  /// Called during pointer-move to update the drag selection extent.
  void handleDragUpdate(
    String documentId,
    String blockId,
    int segmentIndex,
    int offset,
  ) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;

    CursorPositionInTextBlock anchor;
    if (selection is SingleCursorSelectionState) {
      final cursor = selection.cursorPos;
      if (cursor is! CursorPositionInTextBlock) return;
      anchor = cursor;
    } else if (selection is RangeSelectionState) {
      final a = selection.anchor;
      if (a is! CursorPositionInTextBlock) return;
      anchor = a;
    } else {
      return;
    }

    _actionService.handleAction(
      SetRangeSelection(
        documentId: documentId,
        anchorBlockId: anchor.blockId,
        anchorSegmentIndex: anchor.segmentIndex,
        anchorOffset: anchor.offset,
        extentBlockId: blockId,
        extentSegmentIndex: segmentIndex,
        extentOffset: offset,
      ),
    );
  }

  /// Called when the drag ends to finalize the selection and sync IME state.
  void handleDragEnd(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document != null) {
      _ime.syncImeState(documentId, document);
    }
  }

  /// Swaps anchor and extent of the current [RangeSelectionState].
  ///
  /// Used on mobile when the user long-presses on the anchor cursor: we swap
  /// so the "grabbed" end becomes the extent (the one that moves during drag),
  /// and the former extent becomes the stationary anchor.
  ///
  /// Does nothing if the current selection is not a range.
  void swapSelectionAnchors(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! RangeSelectionState) return;

    document.selection.value = RangeSelectionState(
      anchor: selection.extent,
      extent: selection.anchor,
    );
  }
}
