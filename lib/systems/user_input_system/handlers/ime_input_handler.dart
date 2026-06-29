// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/systems/page_system/page_system.dart';

class ImeInputHandler {
  late final PageSystem _pageSystem;

  final Map<String, ValueNotifier<TextEditingValue>> _imeStates = {};

  VoidCallback? onPlatformImeUpdateNeeded;

  void init(PageSystem pageSystem) {
    _pageSystem = pageSystem;
  }

  ValueNotifier<TextEditingValue> getImeState(String pageId) {
    return _imeStates.putIfAbsent(
      pageId,
      () => ValueNotifier(TextEditingValue.empty),
    );
  }

  void syncImeState(String pageId) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    getImeState(pageId).value = _computeTextEditingValue(page);
    onPlatformImeUpdateNeeded?.call();
  }

  void handleTextDeltas(String pageId, List<TextEditingDelta> deltas) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    for (final delta in deltas) {
      switch (delta) {
        case TextEditingDeltaInsertion():
          _handleInsertion(page, pageId, delta);
        case TextEditingDeltaReplacement():
          _handleReplacement(page, pageId, delta);
        case TextEditingDeltaNonTextUpdate():
          _handleNonTextUpdate(page, pageId, delta);
        default:
          break;
      }
    }
  }

  void _handleInsertion(
    PageEntity page,
    String pageId,
    TextEditingDeltaInsertion delta,
  ) {
    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );

    _pageSystem.editing.insertText(flatOffset, delta.textInserted);

    getImeState(pageId).value = delta.apply(getImeState(pageId).value);
  }

  void _handleReplacement(
    PageEntity page,
    String pageId,
    TextEditingDeltaReplacement delta,
  ) {
    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    _pageSystem.editing.replaceText(
      delta.replacedRange.start,
      delta.replacedRange.end,
      delta.replacementText,
    );

    getImeState(pageId).value = _computeTextEditingValue(page);
  }

  void _handleNonTextUpdate(
    PageEntity page,
    String pageId,
    TextEditingDeltaNonTextUpdate delta,
  ) {
    if (!delta.selection.isCollapsed) return;

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    _pageSystem.selection.setCursorPosition(delta.selection.baseOffset);

    getImeState(pageId).value = _computeTextEditingValue(page);
  }

  TextEditingValue _computeTextEditingValue(PageEntity page) {
    final buffer = StringBuffer();
    final blockOffsets = <String, int>{};
    final ids = page.flatBlockIds();

    for (var i = 0; i < ids.length; i++) {
      final block = page.getBlockById(ids[i]);
      if (block is! TextBlockEntity) continue;

      blockOffsets[block.id] = buffer.length;
      buffer.write(block.computeAllSegmentsText());
      if (i < ids.length - 1) {
        buffer.write('\n');
      }
    }

    final fullText = buffer.toString();
    final selection = page.selection.value;

    if (selection is SingleCursorSelectionEntity) {
      final cursor = selection.cursorPos;
      if (cursor is CursorPositionInTextBlock) {
        final block = page.getBlockById(cursor.blockId);
        if (block is TextBlockEntity) {
          final blockStart = blockOffsets[cursor.blockId] ?? 0;
          final flatInBlock = block.flatOffsetFromCursor(
            cursor.segmentIndex,
            cursor.offset,
          );
          final globalOffset = blockStart + flatInBlock;
          return TextEditingValue(
            text: fullText,
            selection: TextSelection.collapsed(offset: globalOffset),
          );
        }
      }
    }

    if (selection is RangeSelectionEntity) {
      final anchor = selection.anchor;
      final extent = selection.extent;
      if (anchor is CursorPositionInTextBlock &&
          extent is CursorPositionInTextBlock) {
        final anchorBlock = page.getBlockById(anchor.blockId);
        final extentBlock = page.getBlockById(extent.blockId);
        if (anchorBlock is TextBlockEntity && extentBlock is TextBlockEntity) {
          final anchorStart = blockOffsets[anchor.blockId] ?? 0;
          final extentStart = blockOffsets[extent.blockId] ?? 0;
          final anchorFlat =
              anchorStart +
              anchorBlock.flatOffsetFromCursor(
                anchor.segmentIndex,
                anchor.offset,
              );
          final extentFlat =
              extentStart +
              extentBlock.flatOffsetFromCursor(
                extent.segmentIndex,
                extent.offset,
              );
          return TextEditingValue(
            text: fullText,
            selection: TextSelection(
              baseOffset: anchorFlat,
              extentOffset: extentFlat,
            ),
          );
        }
      }
    }

    return TextEditingValue(text: fullText);
  }
}
