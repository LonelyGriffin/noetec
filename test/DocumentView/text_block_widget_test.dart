// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';

/// Creates a [TextBlock] with a single plain text segment for testing.
TextBlock _createTextBlock({
  String id = 'block-1',
  String text = 'Hello, World!',
}) {
  return TextBlock(
    id: id,
    documentId: 'test-doc',
    parent: ValueNotifier(null),
    segments: ListNotifier(data: [TextSegment(text: text)]),
  );
}

/// Creates a [TextBlock] with multiple segments for testing.
TextBlock _createMultiSegmentBlock({String id = 'block-1'}) {
  return TextBlock(
    id: id,
    documentId: 'test-doc',
    parent: ValueNotifier(null),
    segments: ListNotifier(
      data: [
        const TextSegment(text: 'Hello '),
        const FormattedSegment(text: 'bold', format: TextFormat.bold),
        const TextSegment(text: ' world'),
      ],
    ),
  );
}

/// Pumps a minimal widget tree containing [TextBlockWidget] and returns
/// the [RenderTextBlockContent] render object.
Future<RenderTextBlockContent> _pumpTextBlock(
  WidgetTester tester, {
  required TextBlock block,
  BlockSelectionInfo selectionInfo = const BlockNotSelected(),
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          child: TextBlockWidget(block: block, selectionInfo: selectionInfo),
        ),
      ),
    ),
  );

  return tester.renderObject<RenderTextBlockContent>(
    find.byType(TextBlockWidget),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    testWidgets('has non-zero height for non-empty text', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      final render = await _pumpTextBlock(tester, block: block);

      expect(render.size.height, greaterThan(0));
    });

    testWidgets('width matches constraint width', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      final render = await _pumpTextBlock(tester, block: block);

      expect(render.size.width, 400.0);
    });

    testWidgets('empty text block still has line height', (tester) async {
      final block = _createTextBlock(text: '');
      final render = await _pumpTextBlock(tester, block: block);

      // TextPainter returns line height even for empty text
      expect(render.size.height, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // getPositionForLocalOffset
  // ---------------------------------------------------------------------------
  group('getPositionForLocalOffset', () {
    testWidgets('returns segment 0 offset 0 for top-left position', (
      tester,
    ) async {
      final block = _createTextBlock(text: 'Hello, World!');
      final render = await _pumpTextBlock(tester, block: block);

      final point = render.getPositionForLocalOffset(Offset.zero);

      expect(point, isNotNull);
      expect(point!.segmentIndex, 0);
      expect(point.offset, 0);
    });

    testWidgets('returns non-zero offset for position in middle of text', (
      tester,
    ) async {
      final block = _createTextBlock(text: 'Hello, World!');
      final render = await _pumpTextBlock(tester, block: block);

      // Use a position roughly in the middle of the text
      final midX = render.size.width / 2;
      final midY = render.size.height / 2;
      final point = render.getPositionForLocalOffset(Offset(midX, midY));

      expect(point, isNotNull);
      expect(point!.segmentIndex, 0);
      expect(point.offset, greaterThan(0));
      expect(
        point.offset,
        lessThanOrEqualTo(13),
      ); // "Hello, World!" is 13 chars
    });

    testWidgets('returns correct segment for multi-segment text', (
      tester,
    ) async {
      // Segments: "Hello " (6) + "bold" (4) + " world" (6)
      final block = _createMultiSegmentBlock();
      final render = await _pumpTextBlock(tester, block: block);

      // Position far right should be in a later segment
      final farX = render.size.width - 1;
      final midY = render.size.height / 2;
      final point = render.getPositionForLocalOffset(Offset(farX, midY));

      expect(point, isNotNull);
      // Should be in segment 2 (" world") since we're at the far right
      expect(point!.segmentIndex, 2);
    });

    testWidgets('returns last segment end for position beyond text end', (
      tester,
    ) async {
      final block = _createTextBlock(text: 'Hi');
      final render = await _pumpTextBlock(tester, block: block);

      // Position way beyond text content (block is 400px wide, text is ~20px)
      final point = render.getPositionForLocalOffset(
        Offset(390, render.size.height / 2),
      );

      expect(point, isNotNull);
      expect(point!.segmentIndex, 0);
      expect(point.offset, 2); // "Hi" is 2 chars, offset at end
    });
  });

  // ---------------------------------------------------------------------------
  // Smoke tests — renders without crashing for each BlockSelectionInfo variant
  // ---------------------------------------------------------------------------
  group('renders without crashing', () {
    testWidgets('with BlockNotSelected', (tester) async {
      final block = _createTextBlock();
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockNotSelected(),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockFullySelected', (tester) async {
      final block = _createTextBlock();
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockFullySelected(),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockWithCursor at start', (tester) async {
      final block = _createTextBlock();
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockWithCursor(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 0,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockWithCursor at end', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockWithCursor(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 5,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockWithRange', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockWithRange(
          anchorCursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 1,
          ),
          extentCursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 4,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockSelectedFromStart', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockSelectedFromStart(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 3,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockSelectedToEnd', (tester) async {
      final block = _createTextBlock(text: 'Hello');
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockSelectedToEnd(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 0,
            offset: 2,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockSelectedToEnd on multi-segment block', (
      tester,
    ) async {
      final block = _createMultiSegmentBlock();
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockSelectedToEnd(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 1,
            offset: 2,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });

    testWidgets('with BlockSelectedFromStart on multi-segment block', (
      tester,
    ) async {
      final block = _createMultiSegmentBlock();
      await _pumpTextBlock(
        tester,
        block: block,
        selectionInfo: const BlockSelectedFromStart(
          cursorPos: CursorPositionInTextBlock(
            blockId: 'block-1',
            segmentIndex: 2,
            offset: 3,
          ),
        ),
      );

      expect(find.byType(TextBlockWidget), findsOneWidget);
    });
  });
}
