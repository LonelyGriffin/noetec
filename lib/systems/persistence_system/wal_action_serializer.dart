// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import '../../entity/page/page_edit_action.dart';

class WalActionSerializer {
  const WalActionSerializer();

  Map<String, dynamic> toJson(PageEditAction action) {
    final base = <String, dynamic>{'type': typeOf(action)};
    return switch (action) {
      InsertTextAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_offset': action.flatOffset,
        'text': action.text,
      },
      DeleteTextBackAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_offset': action.flatOffset,
      },
      DeleteTextForwardAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_offset': action.flatOffset,
      },
      BlockSplitAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_offset': action.splitOffset,
      },
      ReplaceTextAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_start': action.flatStart,
        'flat_end': action.flatEnd,
        'replacement': action.replacement,
      },
      DeleteSelectionAction() => {...base, 'block_id': action.blockId},
      PasteTextAction() => {
        ...base,
        'block_id': action.blockId,
        'flat_offset': action.flatOffset,
        'clipboard_content': action.clipboardContent,
      },
    };
  }

  String typeOf(PageEditAction action) => switch (action) {
    InsertTextAction() => 'insert_text',
    DeleteTextBackAction() => 'delete_text_back',
    DeleteTextForwardAction() => 'delete_text_forward',
    BlockSplitAction() => 'block_split',
    ReplaceTextAction() => 'replace_text',
    DeleteSelectionAction() => 'delete_selection',
    PasteTextAction() => 'paste_text',
  };

  PageEditAction fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final blockId = json['block_id'] as String;
    return switch (type) {
      'insert_text' => InsertTextAction(
        blockId: blockId,
        flatOffset: json['flat_offset'] as int,
        text: json['text'] as String,
      ),
      'delete_text_back' => DeleteTextBackAction(
        blockId: blockId,
        flatOffset: json['flat_offset'] as int,
      ),
      'delete_text_forward' => DeleteTextForwardAction(
        blockId: blockId,
        flatOffset: json['flat_offset'] as int,
      ),
      'block_split' => BlockSplitAction(
        blockId: blockId,
        splitOffset: json['flat_offset'] as int,
      ),
      'replace_text' => ReplaceTextAction(
        blockId: blockId,
        flatStart: json['flat_start'] as int,
        flatEnd: json['flat_end'] as int,
        replacement: json['replacement'] as String,
      ),
      'delete_selection' => DeleteSelectionAction(blockId: blockId),
      'paste_text' => PasteTextAction(
        blockId: blockId,
        flatOffset: json['flat_offset'] as int,
        clipboardContent: json['clipboard_content'] as String,
      ),
      _ => throw FormatException('Unknown WAL action type: $type'),
    };
  }
}
