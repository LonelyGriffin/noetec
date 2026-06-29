import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

void main() {
  group('BlockOp', () {
    group('BlockInsert', () {
      test('serializes and deserializes correctly', () {
        const op = BlockInsert(
          blockId: 'block1',
          afterBlockId: 'block0',
          segments: [
            TextSegment(text: 'hello'),
            FormattedSegment(text: 'world', format: TextFormat.bold),
          ],
        );

        final json = op.toJson();
        final restored = BlockOp.fromJson(json);

        expect(restored, isA<BlockInsert>());
        final insert = restored as BlockInsert;
        expect(insert.blockId, 'block1');
        expect(insert.afterBlockId, 'block0');
        expect(insert.segments, hasLength(2));
        expect(insert.segments[0], isA<TextSegment>());
        expect(insert.segments[0].text, 'hello');
        expect(insert.segments[1], isA<FormattedSegment>());
        expect(
          (insert.segments[1] as FormattedSegment).format,
          TextFormat.bold,
        );
      });
    });

    test('fromJson throws FormatException for unknown type', () {
      expect(
        () => BlockOp.fromJson({'type': 'unknown', 'blockId': 'b1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('FileOp', () {
    group('FileCreateOp', () {
      test('serializes and deserializes correctly', () {
        const op = FileCreateOp(
          pageId: 'page1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'block1',
              afterBlockId: null,
              segments: [TextSegment(text: 'initial')],
            ),
          ],
        );

        final json = op.toJson();
        final restored = FileOp.fromJson(json);

        expect(restored, isA<FileCreateOp>());
        final create = restored as FileCreateOp;
        expect(create.pageId, 'page1');
        expect(create.initialBlocks, hasLength(1));
        expect(create.initialBlocks[0].blockId, 'block1');
        expect(create.initialBlocks[0].segments.first.text, 'initial');
      });

      test('handles empty initial blocks', () {
        const op = FileCreateOp(pageId: 'page1', initialBlocks: []);

        final json = op.toJson();
        final restored = FileOp.fromJson(json) as FileCreateOp;
        expect(restored.initialBlocks, isEmpty);
      });
    });

    test('fromJson throws FormatException for unknown type', () {
      expect(
        () => FileOp.fromJson({'type': 'unknown'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('TextBlockSnapshot', () {
    test('serializes and deserializes correctly', () {
      const snapshot = TextBlockSnapshot(
        blockId: 'block1',
        afterBlockId: 'block0',
        segments: [
          TextSegment(text: 'hello'),
          FormattedSegment(text: 'world', format: TextFormat.italic),
        ],
      );

      final json = snapshot.toJson();
      final restored = TextBlockSnapshot.fromJson(json);

      expect(restored.blockId, 'block1');
      expect(restored.afterBlockId, 'block0');
      expect(restored.segments, hasLength(2));
      expect(restored.segments[1], isA<FormattedSegment>());
    });
  });

  group('OpLogEntry', () {
    test('serializes and deserializes edit entry', () {
      final hlc = Hlc.now(null, 'device1');
      final entry = OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: null,
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [const BlockDelete(blockId: 'block1')],
        fileOp: null,
        fileHash: 'sha256:abc123',
        deviceId: 'device1',
      );

      final json = entry.toJson();
      final restored = OpLogEntry.fromJson(json);

      expect(restored.version, 1);
      expect(restored.hlc, hlc);
      expect(restored.parent, isNull);
      expect(restored.type, OpEntryType.edit);
      expect(restored.blockOps, hasLength(1));
      expect(restored.fileOp, isNull);
      expect(restored.fileHash, 'sha256:abc123');
      expect(restored.deviceId, 'device1');
    });

    test('serializes all OpEntryType values', () {
      for (final type in OpEntryType.values) {
        final hlc = Hlc.now(null, 'device1');
        final entry = OpLogEntry(
          version: 1,
          hlc: hlc,
          parent: null,
          parentB: null,
          type: type,
          blockOps: [],
          fileOp: null,
          fileHash: null,
          deviceId: 'device1',
        );

        final json = entry.toJson();
        final restored = OpLogEntry.fromJson(json);
        expect(restored.type, type);
      }
    });
  });
}
