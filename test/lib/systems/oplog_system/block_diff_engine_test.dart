import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/block_diff_engine.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

TextBlockEntity _makeBlock(String id, String text) => TextBlockEntity(
  id: id,
  segments: [TextSegment(text: text)],
);

TextBlockEntity _makeFormattedBlock(
  String id,
  String text,
  TextFormat format,
) => TextBlockEntity(
  id: id,
  segments: [FormattedSegment(text: text, format: format)],
);

void main() {
  group('BlockDiffEngine —', () {
    test('empty lists produce no ops', () {
      final ops = BlockDiffEngine.compute([], []);
      expect(ops, isEmpty);
    });

    test('no changes produce no ops', () {
      final blocks = [_makeBlock('b1', 'hello')];
      final ops = BlockDiffEngine.compute(blocks, blocks);
      expect(ops, isEmpty);
    });

    test('insertion produces BlockInsert with correct afterBlockId', () {
      final current = [_makeBlock('b1', 'hello'), _makeBlock('b2', 'world')];
      final ops = BlockDiffEngine.compute([], current);

      expect(ops, hasLength(2));
      expect(ops[0], isA<BlockInsert>());
      expect((ops[0] as BlockInsert).afterBlockId, isNull);
      expect(ops[1], isA<BlockInsert>());
      expect((ops[1] as BlockInsert).afterBlockId, 'b1');
    });

    test('insertion at start has null afterBlockId', () {
      final prev = [_makeBlock('b2', 'world')];
      final current = [_makeBlock('b1', 'hello'), _makeBlock('b2', 'world')];
      final ops = BlockDiffEngine.compute(prev, current);

      final inserts = ops.whereType<BlockInsert>().toList();
      expect(inserts, hasLength(1));
      expect(inserts.first.blockId, 'b1');
      expect(inserts.first.afterBlockId, isNull);
    });

    test('deletion produces BlockDelete', () {
      final prev = [_makeBlock('b1', 'hello')];
      final ops = BlockDiffEngine.compute(prev, []);

      expect(ops, hasLength(1));
      expect(ops.first, isA<BlockDelete>());
      expect((ops.first as BlockDelete).blockId, 'b1');
    });

    test('update produces BlockUpdate', () {
      final prev = [_makeBlock('b1', 'hello')];
      final current = [_makeBlock('b1', 'world')];
      final ops = BlockDiffEngine.compute(prev, current);

      expect(ops, hasLength(1));
      expect(ops.first, isA<BlockUpdate>());
      expect((ops.first as BlockUpdate).segments.first.text, 'world');
    });

    test('reorder produces BlockMove', () {
      final prev = [
        _makeBlock('b1', 'a'),
        _makeBlock('b2', 'b'),
        _makeBlock('b3', 'c'),
      ];
      final current = [
        _makeBlock('b2', 'b'),
        _makeBlock('b1', 'a'),
        _makeBlock('b3', 'c'),
      ];
      final ops = BlockDiffEngine.compute(prev, current);

      expect(ops.whereType<BlockMove>(), isNotEmpty);
    });

    test('simultaneous move and update', () {
      final prev = [_makeBlock('b1', 'a'), _makeBlock('b2', 'b')];
      final current = [_makeBlock('b2', 'b-modified'), _makeBlock('b1', 'a')];
      final ops = BlockDiffEngine.compute(prev, current);

      expect(ops.whereType<BlockMove>(), isNotEmpty);
      expect(ops.whereType<BlockUpdate>(), isNotEmpty);
    });

    test('blocksEqual returns true for identical content', () {
      final a = _makeBlock('b1', 'hello');
      final b = _makeBlock('b1', 'hello');
      expect(BlockDiffEngine.blocksEqual(a, b), isTrue);
    });

    test('blocksEqual returns false for different text', () {
      final a = _makeBlock('b1', 'hello');
      final b = _makeBlock('b1', 'world');
      expect(BlockDiffEngine.blocksEqual(a, b), isFalse);
    });

    test('blocksEqual returns false for different format', () {
      final a = _makeBlock('b1', 'hello');
      final b = _makeFormattedBlock('b1', 'hello', TextFormat.bold);
      expect(BlockDiffEngine.blocksEqual(a, b), isFalse);
    });

    test('blocksEqual returns true for same format', () {
      final a = _makeFormattedBlock('b1', 'hello', TextFormat.bold);
      final b = _makeFormattedBlock('b1', 'hello', TextFormat.bold);
      expect(BlockDiffEngine.blocksEqual(a, b), isTrue);
    });

    test('blocksEqual returns false for different segment count', () {
      final a = TextBlockEntity(
        id: 'b1',
        segments: [
          const TextSegment(text: 'hello'),
          const TextSegment(text: ' world'),
        ],
      );
      final b = TextBlockEntity(
        id: 'b1',
        segments: [const TextSegment(text: 'hello world')],
      );
      expect(BlockDiffEngine.blocksEqual(a, b), isFalse);
    });

    test('blocksEqual handles LinkSegment', () {
      final a = TextBlockEntity(
        id: 'b1',
        segments: [const LinkSegment(text: 'click', url: 'https://a.com')],
      );
      final b = TextBlockEntity(
        id: 'b1',
        segments: [const LinkSegment(text: 'click', url: 'https://a.com')],
      );
      expect(BlockDiffEngine.blocksEqual(a, b), isTrue);
    });

    test('blocksEqual returns false for different link URL', () {
      final a = TextBlockEntity(
        id: 'b1',
        segments: [const LinkSegment(text: 'click', url: 'https://a.com')],
      );
      final b = TextBlockEntity(
        id: 'b1',
        segments: [const LinkSegment(text: 'click', url: 'https://b.com')],
      );
      expect(BlockDiffEngine.blocksEqual(a, b), isFalse);
    });

    test('multiple inserts keep correct afterBlockId chain', () {
      final prev = [_makeBlock('b1', 'a')];
      final current = [
        _makeBlock('b1', 'a'),
        _makeBlock('b2', 'b'),
        _makeBlock('b3', 'c'),
      ];
      final ops = BlockDiffEngine.compute(prev, current);

      final inserts = ops.whereType<BlockInsert>().toList();
      expect(inserts, hasLength(2));
      expect(inserts[0].blockId, 'b2');
      expect(inserts[0].afterBlockId, 'b1');
      expect(inserts[1].blockId, 'b3');
      expect(inserts[1].afterBlockId, 'b2');
    });
  });
}
