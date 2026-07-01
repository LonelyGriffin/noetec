import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';

void main() {
  group('OpLogSerializer', () {
    const serializer = OpLogSerializer();

    group('encode/decode', () {
      test('encodes and decodes edit entry', () {
        final entry = OpLogEntry(
          version: 1,
          hlc: Hlc.fromKey('1234-0001-dev1'),
          parent: Hlc.fromKey('1233-0000-dev1'),
          parentB: null,
          type: OpEntryType.edit,
          blockOps: const [BlockDelete(blockId: 'b1')],
          fileOp: null,
          fileHash: 'sha256:abc',
          deviceId: 'dev1',
        );

        final encoded = serializer.encode(entry);
        final decoded = serializer.decode(encoded);

        expect(decoded.version, 1);
        expect(decoded.hlc.toKey(), '1234-0001-dev1');
        expect(decoded.parent?.toKey(), '1233-0000-dev1');
        expect(decoded.parentB, isNull);
        expect(decoded.type, OpEntryType.edit);
        expect(decoded.blockOps, hasLength(1));
        expect(decoded.blockOps!.first, isA<BlockDelete>());
        expect(decoded.fileOp, isNull);
        expect(decoded.fileHash, 'sha256:abc');
        expect(decoded.deviceId, 'dev1');
      });

      test('throws FormatException for invalid JSON', () {
        expect(
          () => serializer.decode('not json'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for missing hlc', () {
        expect(
          () => serializer.decode('{"type":"edit","device":"d"}'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for missing type', () {
        expect(
          () => serializer.decode('{"hlc":"1000-0000-d","device":"d"}'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for missing device', () {
        expect(
          () => serializer.decode('{"hlc":"1000-0000-d","type":"edit"}'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for non-object JSON', () {
        expect(
          () => serializer.decode('"string"'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('segmentToJson/segmentFromJson', () {
      test('plain segment', () {
        const segment = TextSegment(text: 'hello');
        final json = serializer.segmentToJson(segment);
        final restored = serializer.segmentFromJson(json);

        expect(restored, isA<TextSegment>());
        expect(restored.text, 'hello');
        expect(json['format'], 0);
      });

      test('handles missing format gracefully', () {
        final restored = serializer.segmentFromJson({'text': 'plain'});
        expect(restored, isA<TextSegment>());
        expect(restored.text, 'plain');
      });
    });
  });
}
