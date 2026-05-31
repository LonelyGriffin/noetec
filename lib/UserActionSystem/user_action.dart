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

/// Move cursor within a text block.
@immutable
class MoveCursor extends UserAction {
  final String documentId;
  final CursorMoveDirection direction;

  const MoveCursor({
    required this.documentId,
    required this.direction,
  });
}

enum CursorMoveDirection { left, right }
