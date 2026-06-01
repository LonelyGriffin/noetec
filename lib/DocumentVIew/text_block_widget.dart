// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';

class TextBlockWidget extends LeafRenderObjectWidget {
  const TextBlockWidget({
    super.key,
    required this.block,
    required this.selectionInfo,
    this.onTextClick,
  });

  final TextBlock block;
  final BlockSelectionInfo selectionInfo;
  final void Function(String blockId, int segmentIndex, int offset)? onTextClick;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTextBlockContent(
      block: block,
      selectionInfo: selectionInfo,
      onTextClick: onTextClick,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTextBlockContent renderObject,
  ) {
    renderObject.block = block;
    renderObject.selectionInfo = selectionInfo;
    renderObject.onTextClick = onTextClick;
  }
}

class RenderTextBlockContent extends RenderBox {
  TextBlock _block;
  TextBlock get block => _block;
  BlockSelectionInfo _selectionInfo;
  BlockSelectionInfo get selectionInfo => _selectionInfo;

  set selectionInfo(BlockSelectionInfo value) {
    if (_selectionInfo == value) return;
    _selectionInfo = value;
    _updateCursorBlink();
    markNeedsPaint();
  }

  set block(TextBlock value) {
    final sameRef = identical(_block, value);
    if (sameRef) {
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
  void Function(String blockId, int segmentIndex, int offset)? onTextClick;

  // Cursor blink state
  Timer? _blinkTimer;
  bool _cursorVisible = true;

  static const _blinkHalfPeriod = Duration(milliseconds: 500);

  final List<_SegmentIndexMap> _segmentMaps = [];
  TextPainter? _textPainter;
  bool _textLayoutDirty = true;

  final _baseTextStyle = TextStyle(color: Color.fromARGB(255, 14, 14, 14));
  final _cursorColor = const Color(0xFF0066CC);
  final _cursorWidth = 2.0;
  final _selectionColor = const Color(0xFFB3D9FF);

  RenderTextBlockContent({
    required TextBlock block,
    required BlockSelectionInfo selectionInfo,
    this.onTextClick,
  }) : _selectionInfo = selectionInfo, _block = block {
    _block.segments.addListener(_onSegmentsChanged);
    _updateCursorBlink();
  }

  /// Starts or stops the blink timer based on current selectionInfo.
  /// Blink is active only for a collapsed cursor (BlockWithCursor).
  /// For range selections the cursor is always visible, no blinking needed.
  void _updateCursorBlink() {
    if (_selectionInfo is BlockWithCursor) {
      _startBlink();
    } else {
      _stopBlink();
    }
  }

  void _startBlink() {
    // Reset so the cursor is immediately visible when it first appears
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
    // Ensure cursor is visible when blink stops (e.g. selection extended to range)
    _cursorVisible = true;
  }

  void _onSegmentsChanged() {
    _textLayoutDirty = true;
    markNeedsLayout();
  }

  TextSpan _buildTextSpan() {
    final segments = _block.segments.value;
    if (segments.isEmpty) {
      return TextSpan(text: '', style: _baseTextStyle);
    }

    _segmentMaps.clear();
    int currentOffset = 0;

    final children = <InlineSpan>[];
    for (int i = 0; i < segments.length; i++) {
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

    return TextSpan(children: children, style: _baseTextStyle);
  }

  String _getSegmentText(TextSegment segment) {
    return switch (segment) {
      TextSegment(:final text) => text,
    };
  }

  TextStyle _getSegmentStyle(TextSegment segment) {
    return switch (segment) {
      FormattedSegment(:final format) => _buildFormattedStyle(format),
      LinkSegment() => _baseTextStyle.copyWith(
        color: const Color(0xFF0066CC),
        decoration: TextDecoration.underline,
      ),
      TextSegment() => _baseTextStyle,
    };
  }

  TextStyle _buildFormattedStyle(TextFormat format) {
    var result = _baseTextStyle.copyWith();
    if (format.value & TextFormat.bold.value != 0) {
      result = result.copyWith(fontWeight: FontWeight.bold);
    }
    if (format.value & TextFormat.italic.value != 0) {
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
    for (int i = 0; i < _segmentMaps.length; i++) {
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

  void _handleTextClick(PointerEvent event) {
    final localPosition = event.localPosition;
    final textPosition = _textPainter!.getPositionForOffset(localPosition);
    final characterIndex = textPosition.offset;
    final interactionPoint = _resolveTextInteractionPoint(characterIndex);

    if (interactionPoint == null) {
      return;
    }

    onTextClick?.call(_block.id, interactionPoint.segmentIndex, interactionPoint.offset);
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
  void paint(PaintingContext context, Offset paintOffset) {
    if (_textPainter == null) return;

    // Draw text first
    _textPainter!.paint(context.canvas, paintOffset);

    // Draw selection/cursor overlay
    switch (_selectionInfo) {
      case BlockNotSelected():
        // No selection, nothing to draw
        break;
      case BlockFullySelected():
        _paintFullSelection(context.canvas, paintOffset);
      case BlockWithCursor(:final cursorPos):
        if (_cursorVisible) {
          _paintCursor(context.canvas, paintOffset, cursorPos.segmentIndex, cursorPos.offset);
        }
      case BlockWithRange(
          :final fromCursorPos,
          :final toCursorPos
        ):
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          fromCursorPos.segmentIndex,
          fromCursorPos.offset,
          toCursorPos.segmentIndex,
          toCursorPos.offset,
        );
      case BlockWithToCursor(:final cursorPos):
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          0,
          0,
          cursorPos.segmentIndex,
          cursorPos.offset,
        );
      case BlockWithFromCursor(:final cursorPos):
        _paintRangeSelection(
          context.canvas,
          paintOffset,
          cursorPos.segmentIndex,
          cursorPos.offset,
          _block.segments.length - 1,
          _block.segments[_block.segments.length - 1].text.length - 1,
        );
    }
  }

  /// Paints a cursor at the given segment and offset within the segment.
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
    final caretOffset = _textPainter!.getOffsetForCaret(textPosition, caretRect);
    final lineHeight =
        _textPainter!.getFullHeightForCaret(textPosition, caretRect);

    final cursorRect = Rect.fromLTWH(
      blockOffset.dx + caretOffset.dx - _cursorWidth / 2,
      blockOffset.dy + caretOffset.dy,
      _cursorWidth,
      lineHeight,
    );

    canvas.drawRect(cursorRect, Paint()..color = _cursorColor);
  }

  /// Paints a selection range between two positions in the same block.
  void _paintRangeSelection(
    Canvas canvas,
    Offset blockOffset,
    int fromSegmentIndex,
    int fromOffsetInSegment,
    int toSegmentIndex,
    int toOffsetInSegment,
  ) {
    final fromFlatOffset =
        _computeFlatOffset(fromSegmentIndex, fromOffsetInSegment);
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

    // Draw cursor at the end position
    _paintCursor(canvas, blockOffset, toSegmentIndex, toOffsetInSegment);
  }

  /// Paints a highlight over the entire block (for blocks fully selected but without cursors).
  void _paintFullSelection(Canvas canvas, Offset blockOffset) {
    final paint = Paint()..color = _selectionColor;
    canvas.drawRect(
      Rect.fromLTWH(
        blockOffset.dx,
        blockOffset.dy,
        size.width,
        size.height,
      ),
      paint,
    );
  }

  /// Computes the flat character offset from a segment index and offset within that segment.
  /// Returns -1 if the segment index is invalid.
  int _computeFlatOffset(int segmentIndex, int offsetInSegment) {
    if (segmentIndex < 0 || segmentIndex >= _segmentMaps.length) {
      return -1;
    }
    final map = _segmentMaps[segmentIndex];
    final flatOffset = map.startOffset + offsetInSegment;
    // Clamp to valid range
    if (flatOffset < 0) return 0;
    if (flatOffset > _textPainter!.text!.toPlainText().length) {
      return _textPainter!.text!.toPlainText().length;
    }
    return flatOffset;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if ((event.buttons & kPrimaryButton) != 0 && _textPainter != null) {
      _handleTextClick(event);
    }
  }
}

/// Maps segment indices to their character positions in the final rendered text.
/// 
/// This class is used to track the character range for each text segment,
/// allowing quick lookup of which segment a tapped character belongs to.
/// 
/// Example: If segments are ["Hello", " ", "world"], this map stores:
/// - Segment 0: startOffset=0, endOffset=5
/// - Segment 1: startOffset=5, endOffset=6
/// - Segment 2: startOffset=6, endOffset=11
class _SegmentIndexMap {
  /// Index of the segment in the block's segments list
  final int segmentIndex;
  
  /// Character offset where this segment starts in the rendered text
  final int startOffset;
  
  /// Character offset where this segment ends in the rendered text
  final int endOffset;

  _SegmentIndexMap({
    required this.segmentIndex,
    required this.startOffset,
    required this.endOffset,
  });
}


class TextInteractionPoint {
  int segmentIndex;
  // Character offset within the segment 
  // if segment is last offset may be equal to segment text length 
  // indicating interaction at the end of the paragraph
  int offset; 
  TextInteractionPoint({required this.segmentIndex, required this.offset});
}
