// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/page_system/segment_utils.dart';

class PageClipboardSubsystem {
  final PageSystem _pageSystem;
  final MarkdownSystem _markdownSystem;
  final IIdService _idService;

  PageClipboardSubsystem(
    this._pageSystem,
    this._markdownSystem,
    this._idService,
  );

  String? copy() {
    final page = _pageSystem.getActivePage();
    if (page == null) return null;

    final markdown = _extractSelectedMarkdown(page);
    return markdown;
  }

  void cut() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    final markdown = _extractSelectedMarkdown(page);
    if (markdown == null) return;

    _pageSystem.editing.deleteSelection();
  }

  String? getCutMarkdown() {
    final page = _pageSystem.getActivePage();
    if (page == null) return null;
    return _extractSelectedMarkdown(page);
  }

  void paste(String markdown) {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    if (page.selection.value is RangeSelectionEntity) {
      _pageSystem.editing.deleteSelection();
    }

    final selection = page.selection.value;
    if (selection is! SingleCursorSelectionEntity) return;

    final cursor = selection.cursorPos;
    if (cursor is! CursorPositionInTextBlock) return;

    final parsedBlocks = _markdownSystem.parseMarkdown(markdown);

    if (parsedBlocks.isEmpty) return;

    if (parsedBlocks.length == 1) {
      _insertSegmentsAtCursor(page, cursor, parsedBlocks.first.segments);
    } else {
      _insertBlocksAtCursor(page, cursor, parsedBlocks);
    }
  }

  String? _extractSelectedMarkdown(PageEntity page) {
    final selection = page.selection.value;
    if (selection is! RangeSelectionEntity) return null;

    final anchor = selection.anchor;
    final extent = selection.extent;
    if (anchor is! CursorPositionInTextBlock ||
        extent is! CursorPositionInTextBlock) {
      return null;
    }

    final (first, last) = orderedCursors(page, anchor, extent);
    if (first == null || last == null) return null;

    if (first.blockId == last.blockId) {
      final block = page.getBlockById(first.blockId);
      if (block is! TextBlockEntity) return null;

      final firstFlat = block.flatOffsetFromCursor(
        first.segmentIndex,
        first.offset,
      );
      final lastFlat = block.flatOffsetFromCursor(
        last.segmentIndex,
        last.offset,
      );

      return _markdownSystem.serializeBlocks(
        [block],
        ranges: [(firstFlat, lastFlat)],
      );
    }

    final ids = page.flatBlockIds();
    final firstIdx = ids.indexOf(first.blockId);
    final lastIdx = ids.indexOf(last.blockId);

    final blocks = <TextBlockEntity>[];
    final ranges = <(int, int)?>[];

    for (var i = firstIdx; i <= lastIdx; i++) {
      final block = page.getBlockById(ids[i]);
      if (block is! TextBlockEntity) continue;

      if (i == firstIdx) {
        final firstFlat = block.flatOffsetFromCursor(
          first.segmentIndex,
          first.offset,
        );
        blocks.add(block);
        ranges.add((firstFlat, block.computeAllSegmentsText().length));
      } else if (i == lastIdx) {
        final lastFlat = block.flatOffsetFromCursor(
          last.segmentIndex,
          last.offset,
        );
        blocks.add(block);
        ranges.add((0, lastFlat));
      } else {
        blocks.add(block);
        ranges.add(null);
      }
    }

    return _markdownSystem.serializeBlocks(blocks, ranges: ranges);
  }

  void _insertSegmentsAtCursor(
    PageEntity page,
    CursorPositionInTextBlock cursor,
    List<TextSegment> pasteSegments,
  ) {
    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final segs = List.of(block.segments);

    final (before, after) = splitSegmentsAt(segs, flatOffset);

    final newSegs = [...before, ...pasteSegments, ...after];
    final normalized = normalizeSegments(newSegs);

    block.segments.replaceRange(0, block.segments.length, normalized);

    final pastedLength = pasteSegments.fold<int>(
      0,
      (sum, s) => sum + s.text.length,
    );
    final newCursorFlat = flatOffset + pastedLength;

    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: block.cursorPosFromFlatOffset(newCursorFlat),
    );
  }

  void _insertBlocksAtCursor(
    PageEntity page,
    CursorPositionInTextBlock cursor,
    List<TextBlockEntity> pasteBlocks,
  ) {
    final block = page.getBlockById(cursor.blockId);
    if (block is! TextBlockEntity) return;

    final flatOffset = block.flatOffsetFromCursor(
      cursor.segmentIndex,
      cursor.offset,
    );
    final segs = List.of(block.segments);

    final (before, after) = splitSegmentsAt(segs, flatOffset);

    final firstPasteSegs = List.of(pasteBlocks.first.segments);
    final currentBlockNewSegs = [...before, ...firstPasteSegs];
    final currentNormalized = normalizeSegments(currentBlockNewSegs);
    block.segments.replaceRange(0, block.segments.length, currentNormalized);

    final siblings = block.parentId == null
        ? page.rootBlocks
        : (page.getBlockById(block.parentId!)?.children ?? page.rootBlocks);
    var insertIdx = siblings.indexOf(block) + 1;

    for (var i = 1; i < pasteBlocks.length - 1; i++) {
      final middleBlock = pasteBlocks[i];
      page.addBlockAt(middleBlock, insertIdx);
      insertIdx++;
    }

    final lastPasteSegs = List.of(pasteBlocks.last.segments);
    final afterBlockSegs = [...lastPasteSegs, ...after];
    final afterNormalized = normalizeSegments(afterBlockSegs);

    final newBlock = TextBlockEntity(
      id: _idService.generateId(),
      parentId: block.parentId,
      segments: afterNormalized,
    );
    page.addBlockAt(newBlock, insertIdx);

    final lastPastedLen = lastPasteSegs.fold<int>(
      0,
      (sum, s) => sum + s.text.length,
    );
    page.selection.value = SingleCursorSelectionEntity(
      cursorPos: newBlock.cursorPosFromFlatOffset(lastPastedLen),
    );
  }
}
