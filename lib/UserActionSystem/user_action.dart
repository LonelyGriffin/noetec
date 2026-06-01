// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
sealed class UserAction {
  const UserAction();
}

/// User inserted text at a position in a text block.
///
/// [flatOffset] is the character offset within the block's concatenated
/// segment text where [text] should be spliced in.
@immutable
class InsertText extends UserAction {
  final String documentId;
  final String blockId;
  final int flatOffset;
  final String text;

  const InsertText({
    required this.documentId,
    required this.blockId,
    required this.flatOffset,
    required this.text,
  });
}

/// User clicked on a position in a text block.
@immutable
class ClickOnTextBlock extends UserAction {
  final String documentId;
  final String blockId;
  final int segmentIndex;
  final int offset;

  const ClickOnTextBlock({
    required this.documentId,
    required this.blockId,
    required this.segmentIndex,
    required this.offset,
  });
}

/// User pressed Enter to split a block at [splitFlatOffset].
///
/// Text before the offset stays in the current block, text from the offset
/// onwards moves to a new block inserted immediately after.
@immutable
class SplitTextBlock extends UserAction {
  final String documentId;
  final String blockId;
  final int splitFlatOffset;

  const SplitTextBlock({
    required this.documentId,
    required this.blockId,
    required this.splitFlatOffset,
  });
}

/// Delete one character before the cursor (Backspace).
///
/// [flatOffset] is the current cursor position. The character at
/// `flatOffset - 1` is removed. Does nothing if `flatOffset <= 0`.
@immutable
class DeleteTextBack extends UserAction {
  final String documentId;
  final String blockId;
  final int flatOffset;

  const DeleteTextBack({
    required this.documentId,
    required this.blockId,
    required this.flatOffset,
  });
}

/// Delete one character after the cursor (Delete key).
///
/// [flatOffset] is the current cursor position. The character at
/// `flatOffset` is removed. Does nothing if `flatOffset >= totalLength`.
@immutable
class DeleteTextForward extends UserAction {
  final String documentId;
  final String blockId;
  final int flatOffset;

  const DeleteTextForward({
    required this.documentId,
    required this.blockId,
    required this.flatOffset,
  });
}

/// IME autocomplete/suggestion replaced a range of characters in a text block.
///
/// Characters in the half-open range [flatStart]..[flatEnd) are removed and
/// [replacementText] is inserted at [flatStart]. The replacement inherits the
/// format of the first affected segment.
@immutable
class ReplaceText extends UserAction {
  final String documentId;
  final String blockId;
  final int flatStart;
  final int flatEnd;
  final String replacementText;

  const ReplaceText({
    required this.documentId,
    required this.blockId,
    required this.flatStart,
    required this.flatEnd,
    required this.replacementText,
  });
}

/// Platform IME moved the cursor to a specific flat offset (e.g. after
/// accepting an autocomplete suggestion that did not change the text).
@immutable
class SetCursorPosition extends UserAction {
  final String documentId;
  final String blockId;
  final int flatOffset;

  const SetCursorPosition({
    required this.documentId,
    required this.blockId,
    required this.flatOffset,
  });
}

/// Move cursor within a text block.
@immutable
class MoveCursor extends UserAction {
  final String documentId;
  final CursorMoveDirection direction;

  const MoveCursor({required this.documentId, required this.direction});
}

/// Extend the current selection by one character in [direction].
///
/// If the current state is [SingleCursorSelectionState], the cursor becomes
/// the anchor and the extent moves one character in [direction].
/// If the current state is [RangeSelectionState], the anchor stays and the
/// extent moves one character in [direction].
/// If anchor == extent after the move, collapses to [SingleCursorSelectionState].
@immutable
class ExtendSelection extends UserAction {
  final String documentId;
  final CursorMoveDirection direction;

  const ExtendSelection({required this.documentId, required this.direction});
}

/// Set a range selection with explicit anchor and extent positions.
///
/// Used for Shift+Click and mouse drag selection.
/// If [anchor] == [extent], collapses to [SingleCursorSelectionState].
@immutable
class SetRangeSelection extends UserAction {
  final String documentId;
  final String anchorBlockId;
  final int anchorSegmentIndex;
  final int anchorOffset;
  final String extentBlockId;
  final int extentSegmentIndex;
  final int extentOffset;

  const SetRangeSelection({
    required this.documentId,
    required this.anchorBlockId,
    required this.anchorSegmentIndex,
    required this.anchorOffset,
    required this.extentBlockId,
    required this.extentSegmentIndex,
    required this.extentOffset,
  });
}

/// Select the entire document (Ctrl+A / Cmd+A).
///
/// Sets a [RangeSelectionState] from the start of the first block to the
/// end of the last block.
@immutable
class SelectAll extends UserAction {
  final String documentId;

  const SelectAll({required this.documentId});
}

/// Delete all content within the current [RangeSelectionState].
///
/// Works on the current selection — no explicit coordinates needed.
/// After deletion the cursor collapses to the start of the deleted range.
/// Does nothing if the current selection is not a range.
@immutable
class DeleteSelection extends UserAction {
  final String documentId;

  const DeleteSelection({required this.documentId});
}

/// Paste content from clipboard into the document.
///
/// [clipboardContent] is the markdown string read from the clipboard.
/// If there is an active range selection, it is deleted first.
/// The parsed blocks/segments are inserted at the cursor position.
@immutable
class Paste extends UserAction {
  final String documentId;
  final String clipboardContent;

  const Paste({required this.documentId, required this.clipboardContent});
}

/// Select the word at the given position in a text block (long press on mobile).
///
/// The word boundary is determined by [TextBlock.wordBoundaryAt].
/// If the position lands on a non-word character, only that character is
/// selected.
@immutable
class SelectWord extends UserAction {
  final String documentId;
  final String blockId;
  final int segmentIndex;
  final int offset;

  const SelectWord({
    required this.documentId,
    required this.blockId,
    required this.segmentIndex,
    required this.offset,
  });
}

enum CursorMoveDirection { left, right }
