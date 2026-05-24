// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

class UserRawTextInputService {
  final OpenedDocumentsManager _documentsManager;
  final UserActionService _actionService;

  UserRawTextInputService({
    required OpenedDocumentsManager documentsManager,
    required UserActionService actionService,
  })  : _documentsManager = documentsManager,
        _actionService = actionService;

  // ---------------------------------------------------------------------------
  // Per-document IME buffer
  // ---------------------------------------------------------------------------

  final Map<String, ValueNotifier<TextEditingValue>> _inputsValues = {};

  // True while notifier.value is being written from an IME-originated update.
  // Used by the widget to suppress the echo-back setEditingState call.
  bool _isApplyingIMEUpdate = false;
  bool get isApplyingIMEUpdate => _isApplyingIMEUpdate;

  ValueNotifier<TextEditingValue>? getInputValue(String id) =>
      _inputsValues[id];

  void registerInputIfNotExist(String id, [TextEditingValue? value]) {
    if (_inputsValues.containsKey(id)) return;
    _inputsValues[id] = ValueNotifier(value ?? const TextEditingValue());
  }

  void unregisterInput(String id) {
    _inputsValues.remove(id);
  }

  // ---------------------------------------------------------------------------
  // Buffer synchronisation: document → IME buffer
  // ---------------------------------------------------------------------------

  /// Reads the currently focused segment from [DocumentModel.selection] and
  /// rebuilds the [TextEditingValue] so the IME reflects only the active
  /// segment's text and the cursor offset within that segment.
  ///
  /// Call this:
  ///   • when the editor widget gains focus
  ///   • when [DocumentModel.selection] changes (e.g. user clicked a new
  ///     position, or an edit moved the cursor to a different segment)
  void syncBufferFromDocument(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final notifier = _inputsValues[documentId];
    if (notifier == null) return;

    final selection = document.selection.value;
    if (selection is! TextSelectionState) {
      // No active cursor — clear the buffer.
      notifier.value = const TextEditingValue();
      return;
    }

    final blockId = selection.from.blockId;
    final block = document.getBlockById(blockId);
    if (block is! TextBlock) {
      notifier.value = const TextEditingValue();
      return;
    }

    final segs = block.segments.value;
    if (segs.isEmpty) {
      notifier.value = const TextEditingValue();
      return;
    }

    final segIdx = selection.from.segmentIndex.clamp(0, segs.length - 1);
    final segText = segs[segIdx].text;
    final cursorOffset = selection.from.offset.clamp(0, segText.length);

    notifier.value = TextEditingValue(
      text: segText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  // ---------------------------------------------------------------------------
  // IME → document
  // ---------------------------------------------------------------------------

  /// Called by [UserRawTextInputWidget] when the IME reports a new
  /// [TextEditingValue] (virtual keyboard, autocorrect, composition, etc.).
  void handleRawTextInputValueUpdate(String documentId, TextEditingValue value) {
    final notifier = _inputsValues[documentId];
    if (notifier == null) return;

    final oldValue = notifier.value;

    // Suppress the echo-back: while this flag is true, _onCurrentValueChanged
    // in the widget will not call setEditingState. This prevents the IME from
    // receiving its own value back, which would reset autocomplete suggestions.
    _isApplyingIMEUpdate = true;
    notifier.value = value;
    _isApplyingIMEUpdate = false;

    // After _propagateTextChange, _handleChangeTextSection writes
    // document.selection, which triggers _onDocumentSelectionChanged →
    // syncBufferFromDocument → notifier.value (flag is already false) →
    // _onCurrentValueChanged → setEditingState once with the canonical value.
    _propagateTextChange(documentId, oldValue, value);
  }

  // ---------------------------------------------------------------------------
  // Hardware keyboard → document
  // ---------------------------------------------------------------------------

  KeyEventResult handleRawTextInputKeyEvent(
    String documentId,
    KeyEvent event,
  ) {
    if (!_inputsValues.containsKey(documentId)) {
      return KeyEventResult.ignored;
    }

    // Only act on key-down events (ignore repeat / up).
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Enter → split block.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _handleEnter(documentId);
      return KeyEventResult.handled;
    }

    final currentValue = _inputsValues[documentId]!.value;
    final text = currentValue.text;
    final selectionStart = currentValue.selection.start.clamp(0, text.length);
    final selectionEnd = currentValue.selection.end.clamp(0, text.length);
    final hasSelection = selectionStart != selectionEnd;

    // Backspace.
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (hasSelection) {
        final newText = text.replaceRange(selectionStart, selectionEnd, '');
        _applyTextUpdate(documentId, currentValue, newText, selectionStart);
      } else if (selectionStart > 0) {
        final newText = text.replaceRange(selectionStart - 1, selectionStart, '');
        _applyTextUpdate(documentId, currentValue, newText, selectionStart - 1);
      } else {
        // Cursor is at offset=0 of the active segment — delete the last char
        // of the previous segment (crossing the segment boundary).
        _handleBackspaceAtSegmentStart(documentId);
      }
      return KeyEventResult.handled;
    }

    // Delete (forward).
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      if (hasSelection) {
        final newText = text.replaceRange(selectionStart, selectionEnd, '');
        _applyTextUpdate(documentId, currentValue, newText, selectionStart);
      } else if (selectionStart < text.length) {
        final newText = text.replaceRange(selectionStart, selectionStart + 1, '');
        _applyTextUpdate(documentId, currentValue, newText, selectionStart);
      } else {
        // Cursor is at the end of the active segment — delete the first char
        // of the next segment (crossing the segment boundary).
        _handleDeleteAtSegmentEnd(documentId);
      }
      return KeyEventResult.handled;
    }

    // Printable character.
    if (event.character != null && event.character!.isNotEmpty) {
      final char = event.character!;
      final newText = text.replaceRange(selectionStart, selectionEnd, char);
      final newCursor = selectionStart + char.length;
      _applyTextUpdate(documentId, currentValue, newText, newCursor);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _handleEnter(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return;

    final selection = document.selection.value;
    if (selection is! TextSelectionState) return;

    final blockId = selection.from.blockId;
    final block = document.getBlockById(blockId);
    if (block is! TextBlock) return;

    final splitOffset = block.flatOffsetFromCursor(
      selection.from.segmentIndex,
      selection.from.offset,
    );

    _actionService.handleAction(
      SplitTextBlock(
        documentId: documentId,
        blockId: blockId,
        splitFlatOffset: splitOffset,
      ),
    );

    // After splitting, the document model has updated selection (to the new
    // block). Sync the IME buffer to reflect the new block's text.
    syncBufferFromDocument(documentId);
  }

  /// Applies a plain-text update within the current segment: writes [newSegText]
  /// into the active segment and dispatches [ChangeTextSection].
  void _applyTextUpdate(
    String documentId,
    TextEditingValue oldValue,
    String newSegText,
    int newCursorOffset,
  ) {
    final newValue = TextEditingValue(
      text: newSegText,
      selection: TextSelection.collapsed(offset: newCursorOffset),
    );
    // Update the IME buffer.
    _inputsValues[documentId]!.value = newValue;

    _propagateTextChange(documentId, oldValue, newValue);
  }

  /// Core bridge: converts a [TextEditingValue] change (scoped to one segment)
  /// into a [ChangeTextSection] action that mutates [TextBlock.segments].
  ///
  /// The IME buffer contains only the text of the active segment, so the new
  /// text in [newValue] replaces exactly that segment. No diff across the
  /// whole paragraph is needed.
  void _propagateTextChange(
    String documentId,
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return; // cursor-only move — no edit

    final ctx = _getEditContext(documentId);
    if (ctx == null) return;

    final (document: document, block: block, selection: selection) = ctx;

    final segIdx = selection.from.segmentIndex;
    final segs = List<TextSegment>.from(block.segments.value);

    // Replace only the active segment's text, preserving its type/format.
    segs[segIdx] = _copySegmentWithText(segs[segIdx], newValue.text);

    final newOffset = newValue.selection.start.clamp(0, newValue.text.length);

    _actionService.handleAction(
      ChangeTextSection(
        documentId: documentId,
        blockId: selection.from.blockId,
        newSegments: segs,
        newSegmentIndex: segIdx,
        newOffset: newOffset,
      ),
    );
  }

  /// Handles Backspace when the cursor is at offset=0 of the active segment.
  ///
  /// Deletes the last character of the closest non-empty segment to the left,
  /// removing any empty segments encountered along the way. Moves the cursor
  /// to the end of that segment after the deletion.
  ///
  /// If there is no segment to the left (cursor is at the very start of the
  /// block), does nothing (TODO: merge with previous block).
  void _handleBackspaceAtSegmentStart(String documentId) {
    final ctx = _getEditContext(documentId);
    if (ctx == null) return;

    final (document: _, block: block, selection: selection) = ctx;

    final segs = List<TextSegment>.from(block.segments.value);
    int targetIdx = selection.from.segmentIndex - 1;

    // Walk left past any empty segments, removing them.
    while (targetIdx >= 0 && segs[targetIdx].text.isEmpty) {
      segs.removeAt(targetIdx);
      targetIdx--;
    }

    if (targetIdx < 0) {
      // No non-empty segment to the left — beginning of block.
      // TODO: merge with previous block.
      return;
    }

    // Delete the last character of the target segment.
    final target = segs[targetIdx];
    final newText = target.text.substring(0, target.text.length - 1);

    if (newText.isEmpty) {
      // Segment became empty — remove it and move cursor to end of the one
      // before it (if any), or stay at start of the block.
      segs.removeAt(targetIdx);
      final newSegIdx = (targetIdx - 1).clamp(0, segs.length - 1);
      final newOffset = segs.isEmpty ? 0 : segs[newSegIdx].text.length;
      _dispatchSegmentEdit(
        documentId: documentId,
        blockId: selection.from.blockId,
        newSegments: segs,
        newSegmentIndex: newSegIdx,
        newOffset: newOffset,
      );
    } else {
      segs[targetIdx] = _copySegmentWithText(target, newText);
      _dispatchSegmentEdit(
        documentId: documentId,
        blockId: selection.from.blockId,
        newSegments: segs,
        newSegmentIndex: targetIdx,
        newOffset: newText.length,
      );
    }
  }

  /// Handles Delete when the cursor is at the end of the active segment.
  ///
  /// Deletes the first character of the closest non-empty segment to the right,
  /// removing any empty segments encountered along the way. The cursor stays
  /// at its current position after the deletion.
  ///
  /// If there is no segment to the right (cursor is at the very end of the
  /// block), does nothing (TODO: merge with next block).
  void _handleDeleteAtSegmentEnd(String documentId) {
    final ctx = _getEditContext(documentId);
    if (ctx == null) return;

    final (document: _, block: block, selection: selection) = ctx;

    final segs = List<TextSegment>.from(block.segments.value);
    final curSegIdx = selection.from.segmentIndex;
    int targetIdx = curSegIdx + 1;

    // Walk right past any empty segments, removing them.
    while (targetIdx < segs.length && segs[targetIdx].text.isEmpty) {
      segs.removeAt(targetIdx);
      // targetIdx stays the same — next element shifted into this position.
    }

    if (targetIdx >= segs.length) {
      // No non-empty segment to the right — end of block.
      // TODO: merge with next block.
      return;
    }

    // Delete the first character of the target segment.
    final target = segs[targetIdx];
    final newText = target.text.substring(1);

    if (newText.isEmpty) {
      // Segment became empty — remove it. Cursor stays in current segment.
      segs.removeAt(targetIdx);
    } else {
      segs[targetIdx] = _copySegmentWithText(target, newText);
    }

    // Cursor stays in current segment at current offset.
    final newSegIdx = curSegIdx.clamp(0, segs.length - 1);
    final newOffset = selection.from.offset.clamp(
      0,
      segs[newSegIdx].text.length,
    );

    _dispatchSegmentEdit(
      documentId: documentId,
      blockId: selection.from.blockId,
      newSegments: segs,
      newSegmentIndex: newSegIdx,
      newOffset: newOffset,
    );
  }

  // ---------------------------------------------------------------------------
  // Shared utilities
  // ---------------------------------------------------------------------------

  /// Resolves the document, block, and selection for [documentId].
  ///
  /// Returns null if any of the required objects are missing or the selection
  /// is not a [TextSelectionState] pointing to a [TextBlock].
  ({
    DocumentModel document,
    TextBlock block,
    TextSelectionState selection,
  })? _getEditContext(String documentId) {
    final document = _documentsManager.getDocument(documentId);
    if (document == null) return null;

    final selection = document.selection.value;
    if (selection is! TextSelectionState) return null;

    final block = document.getBlockById(selection.from.blockId);
    if (block is! TextBlock) return null;

    return (document: document, block: block, selection: selection);
  }

  /// Dispatches a [ChangeTextSection] action with the supplied parameters.
  void _dispatchSegmentEdit({
    required String documentId,
    required String blockId,
    required List<TextSegment> newSegments,
    required int newSegmentIndex,
    required int newOffset,
  }) {
    _actionService.handleAction(
      ChangeTextSection(
        documentId: documentId,
        blockId: blockId,
        newSegments: newSegments,
        newSegmentIndex: newSegmentIndex,
        newOffset: newOffset,
      ),
    );
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
