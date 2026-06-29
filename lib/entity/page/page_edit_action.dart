// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

sealed class PageEditAction {
  String get blockId;
  const PageEditAction();
}

final class InsertTextAction extends PageEditAction {
  @override
  final String blockId;
  final int flatOffset;
  final String text;

  const InsertTextAction({
    required this.blockId,
    required this.flatOffset,
    required this.text,
  });
}

final class DeleteTextBackAction extends PageEditAction {
  @override
  final String blockId;
  final int flatOffset;

  const DeleteTextBackAction({required this.blockId, required this.flatOffset});
}

final class DeleteTextForwardAction extends PageEditAction {
  @override
  final String blockId;
  final int flatOffset;

  const DeleteTextForwardAction({
    required this.blockId,
    required this.flatOffset,
  });
}

final class BlockSplitAction extends PageEditAction {
  @override
  final String blockId;
  final int splitOffset;

  const BlockSplitAction({required this.blockId, required this.splitOffset});
}

final class ReplaceTextAction extends PageEditAction {
  @override
  final String blockId;
  final int flatStart;
  final int flatEnd;
  final String replacement;

  const ReplaceTextAction({
    required this.blockId,
    required this.flatStart,
    required this.flatEnd,
    required this.replacement,
  });
}

final class DeleteSelectionAction extends PageEditAction {
  @override
  final String blockId;

  const DeleteSelectionAction({required this.blockId});
}

final class PasteTextAction extends PageEditAction {
  @override
  final String blockId;
  final String clipboardContent;
  final int flatOffset;

  const PasteTextAction({
    required this.blockId,
    required this.clipboardContent,
    required this.flatOffset,
  });
}
