// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/view/widgets/editor/block_selection_info.dart';

class TextBlockRenderWidget extends LeafRenderObjectWidget {
  const TextBlockRenderWidget({
    super.key,
    required this.block,
    required this.selectionInfo,
    required this.cursorColor,
    required this.selectionColor,
    required this.textStyle,
  });

  final TextBlockEntity block;
  final BlockSelectionInfo selectionInfo;
  final Color cursorColor;
  final Color selectionColor;
  final TextStyle textStyle;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return TextBlockRenderBox(
      block: block,
      selectionInfo: selectionInfo,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      textStyle: textStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    TextBlockRenderBox renderObject,
  ) {
    renderObject.block = block;
    renderObject.selectionInfo = selectionInfo;
    renderObject.cursorColor = cursorColor;
    renderObject.selectionColor = selectionColor;
    renderObject.textStyle = textStyle;
  }
}

class TextBlockRenderBox extends RenderBox {
  TextBlockEntity _block;
  BlockSelectionInfo _selectionInfo;
  Color _cursorColor;
  Color _selectionColor;
  TextStyle _textStyle;

  TextBlockRenderBox({
    required TextBlockEntity block,
    required BlockSelectionInfo selectionInfo,
    required Color cursorColor,
    required Color selectionColor,
    required TextStyle textStyle,
  }) : _block = block,
       _selectionInfo = selectionInfo,
       _cursorColor = cursorColor,
       _selectionColor = selectionColor,
       _textStyle = textStyle {
    _block.segments.addListener(_onSegmentsChanged);
    _updateCursorBlink();
  }

  String get blockId => _block.id;

  set block(TextBlockEntity value) {
    if (identical(_block, value)) {
      _textLayoutDirty = true;
      markNeedsLayout();
      return;
    }
    _block.segments.removeListener(_onSegmentsChanged);
    _block = value;
    _block.segments.addListener(_onSegmentsChanged);
    _textLayoutDirty = true;
    markNeedsLayout();
  }

  set selectionInfo(BlockSelectionInfo value) {
    if (_selectionInfo == value) return;
    _selectionInfo = value;
    _updateCursorBlink();
    markNeedsPaint();
  }

  set cursorColor(Color value) {
    if (_cursorColor == value) return;
    _cursorColor = value;
    markNeedsPaint();
  }

  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  set textStyle(TextStyle value) {
    if (_textStyle == value) return;
    _textStyle = value;
    _textLayoutDirty = true;
    markNeedsLayout();
  }

  Timer? _blinkTimer;
  bool _cursorVisible = true;
  static const _blinkHalfPeriod = Duration(milliseconds: 500);

  final List<_SegmentIndexMap> _segmentMaps = [];
  TextPainter? _textPainter;
  bool _textLayoutDirty = true;

  static const _cursorWidth = 2.0;

  void _updateCursorBlink() {
    if (_selectionInfo is BlockWithCursor) {
      _startBlink();
    } else {
      _stopBlink();
    }
  }

  void _startBlink() {
    _cursorVisible = true;
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(_blinkHalfPeriod, (_) {
      _cursorVisible = !_cursorVisible;
      if (attached) markNeedsPaint();
    });
  }

  void _stopBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _cursorVisible = true;
  }

  void _onSegmentsChanged() {
    _textLayoutDirty = true;
    markNeedsLayout();
  }

  TextSpan _buildTextSpan() {
    final segments = _block.segments.value;
    if (segments.isEmpty) {
      return TextSpan(text: '', style: _textStyle);
    }

    _segmentMaps.clear();
    var currentOffset = 0;

    final children = <InlineSpan>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final text = _getSegmentText(segment);
      final style = _getSegmentStyle(segment);

      _segmentMaps.add(
        _SegmentIndexMap(
          segmentIndex: i,
          startOffset: currentOffset,
          endOffset: currentOffset + text.length,
        ),
      );

      currentOffset += text.length;
      children.add(TextSpan(text: text, style: style));
    }

    return TextSpan(children: children, style: _textStyle);
  }

  String _getSegmentText(TextSegment segment) {
    return switch (segment) {
      TextSegment(:final text) => text,
    };
  }

  TextStyle _getSegmentStyle(TextSegment segment) {
    return switch (segment) {
      FormattedSegment(:final format) => _buildFormattedStyle(format),
      LinkSegment() => _textStyle.copyWith(
        color: const Color(0xFF0066CC),
        decoration: TextDecoration.underline,
      ),
      TextSegment() => _textStyle,
    };
  }

  TextStyle _buildFormattedStyle(TextFormat format) {
    var result = _textStyle.copyWith();
    if (format.has(TextFormat.bold)) {
      result = result.copyWith(fontWeight: FontWeight.bold);
    }
    if (format.has(TextFormat.italic)) {
      result = result.copyWith(fontStyle: FontStyle.italic);
    }
    return result;
  }

  void _updateTextLayout(double maxWidth) {
    if (_textPainter != null && !_textLayoutDirty) {
      if (_textPainter!.width == maxWidth) return;
    }
    _textLayoutDirty = false;

    final textSpan = _buildTextSpan();

    _textPainter?.dispose();
    _textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    _textPainter!.layout(maxWidth: maxWidth);
  }

  int _findSegmentIndex(int offset) {
    for (var i = 0; i < _segmentMaps.length; i++) {
      final map = _segmentMaps[i];
      if (offset >= map.startOffset && offset < map.endOffset) {
        return i;
      }
    }
    if (_segmentMaps.isNotEmpty && offset == _segmentMaps.last.endOffset) {
      return _segmentMaps.length - 1;
    }
    return -1;
  }

  TextInteractionPoint? _resolveTextInteractionPoint(int characterIndex) {
    final segmentIndex = _findSegmentIndex(characterIndex);
    if (segmentIndex != -1) {
      final map = _segmentMaps[segmentIndex];
      final charIndexInSegment = characterIndex - map.startOffset;
      return TextInteractionPoint(
        segmentIndex: segmentIndex,
        offset: charIndexInSegment,
      );
    }
    return null;
  }

  TextInteractionPoint? getPositionForLocalOffset(Offset localOffset) {
    if (_textPainter == null) return null;
    final textPosition = _textPainter!.getPositionForOffset(localOffset);
    return _resolveTextInteractionPoint(textPosition.offset);
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _block.segments.removeListener(_onSegmentsChanged);
    _textPainter?.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    _updateTextLayout(maxWidth);

    final textHeight = _textPainter?.height ?? 0;
    size = constraints.constrain(Size(maxWidth, textHeight));
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void paint(PaintingContext context, Offset paintOffset) {
    if (_textPainter == null) return;

    switch (_selectionInfo) {
      case BlockNotSelected():
        break;
      case BlockFullySelected():
        _paintFullSelection(context.canvas, paintOffset);
      case BlockWithCursor():
        break;
      case BlockWithRange(:final anchorCursorPos, :final extentCursorPos):
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          anchorCursorPos.segmentIndex,
          anchorCursorPos.offset,
          extentCursorPos.segmentIndex,
          extentCursorPos.offset,
        );
      case BlockSelectedFromStart(:final cursorPos):
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          0,
          0,
          cursorPos.segmentIndex,
          cursorPos.offset,
        );
      case BlockSelectedToEnd(:final cursorPos):
        final lastSegmentIndex = _segmentMaps.length - 1;
        final lastSegmentEnd = lastSegmentIndex >= 0
            ? _segmentMaps[lastSegmentIndex].endOffset -
                  _segmentMaps[lastSegmentIndex].startOffset
            : 0;
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          cursorPos.segmentIndex,
          cursorPos.offset,
          lastSegmentIndex >= 0 ? lastSegmentIndex : 0,
          lastSegmentEnd,
        );
    }

    _textPainter!.paint(context.canvas, paintOffset);

    switch (_selectionInfo) {
      case BlockWithCursor(:final cursorPos):
        if (_cursorVisible) {
          _paintCursor(
            context.canvas,
            paintOffset,
            cursorPos.segmentIndex,
            cursorPos.offset,
          );
        }
      case BlockWithRange(:final anchorCursorPos, :final extentCursorPos):
        _paintCursor(
          context.canvas,
          paintOffset,
          anchorCursorPos.segmentIndex,
          anchorCursorPos.offset,
        );
        _paintCursor(
          context.canvas,
          paintOffset,
          extentCursorPos.segmentIndex,
          extentCursorPos.offset,
        );
      case BlockSelectedFromStart(:final cursorPos):
        _paintCursor(
          context.canvas,
          paintOffset,
          cursorPos.segmentIndex,
          cursorPos.offset,
        );
      case BlockSelectedToEnd(:final cursorPos):
        _paintCursor(
          context.canvas,
          paintOffset,
          cursorPos.segmentIndex,
          cursorPos.offset,
        );
      default:
        break;
    }
  }

  void _paintCursor(
    Canvas canvas,
    Offset blockOffset,
    int segmentIndex,
    int charOffsetInSegment,
  ) {
    final flatOffset = _computeFlatOffset(segmentIndex, charOffsetInSegment);
    if (flatOffset == -1) return;

    final textPosition = TextPosition(offset: flatOffset);
    final caretRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final caretOffset = _textPainter!.getOffsetForCaret(
      textPosition,
      caretRect,
    );
    final lineHeight = _textPainter!.getFullHeightForCaret(
      textPosition,
      caretRect,
    );

    final cursorRect = Rect.fromLTWH(
      blockOffset.dx + caretOffset.dx - _cursorWidth / 2,
      blockOffset.dy + caretOffset.dy,
      _cursorWidth,
      lineHeight,
    );

    final paint = Paint()..color = _cursorColor;
    canvas.drawRect(cursorRect, paint);
  }

  void _paintRangeSelection(
    Canvas canvas,
    Offset blockOffset,
    int fromSegmentIndex,
    int fromOffsetInSegment,
    int toSegmentIndex,
    int toOffsetInSegment,
  ) {
    final fromFlatOffset = _computeFlatOffset(
      fromSegmentIndex,
      fromOffsetInSegment,
    );
    final toFlatOffset = _computeFlatOffset(toSegmentIndex, toOffsetInSegment);

    if (fromFlatOffset == -1 || toFlatOffset == -1) return;

    final (start, end) = fromFlatOffset <= toFlatOffset
        ? (fromFlatOffset, toFlatOffset)
        : (toFlatOffset, fromFlatOffset);

    final textSelection = TextSelection(baseOffset: start, extentOffset: end);
    final boxes = _textPainter!.getBoxesForSelection(textSelection);

    final paint = Paint()..color = _selectionColor;
    for (final box in boxes) {
      canvas.drawRect(
        Rect.fromLTRB(
          blockOffset.dx + box.left,
          blockOffset.dy + box.top,
          blockOffset.dx + box.right,
          blockOffset.dy + box.bottom,
        ),
        paint,
      );
    }
  }

  void _paintFullSelection(Canvas canvas, Offset blockOffset) {
    final paint = Paint()..color = _selectionColor;
    canvas.drawRect(
      Rect.fromLTWH(blockOffset.dx, blockOffset.dy, size.width, size.height),
      paint,
    );
  }

  int _computeFlatOffset(int segmentIndex, int offsetInSegment) {
    if (segmentIndex < 0 || segmentIndex >= _segmentMaps.length) return -1;
    final map = _segmentMaps[segmentIndex];
    final flatOffset = map.startOffset + offsetInSegment;
    if (flatOffset < 0) return 0;
    final textLength = _textPainter!.text!.toPlainText().length;
    if (flatOffset > textLength) return textLength;
    return flatOffset;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {}
}

class _SegmentIndexMap {
  final int segmentIndex;
  final int startOffset;
  final int endOffset;

  _SegmentIndexMap({
    required this.segmentIndex,
    required this.startOffset,
    required this.endOffset,
  });
}

class TextInteractionPoint {
  final int segmentIndex;
  final int offset;

  TextInteractionPoint({required this.segmentIndex, required this.offset});
}
