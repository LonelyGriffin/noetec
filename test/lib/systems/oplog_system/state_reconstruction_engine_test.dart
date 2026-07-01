import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';

void main() {
  group('StateReconstructionEngine', () {
    test('reconstructs empty state from fileCreate with no blocks', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(pageId: 'p1', initialBlocks: []),
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, createEntry);

      expect(blocks, isEmpty);
    });

    test('reconstructs state from fileCreate with initial blocks', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'Hello')],
            ),
            TextBlockSnapshot(
              blockId: 'b2',
              afterBlockId: 'b1',
              segments: [TextSegment(text: 'World')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, createEntry);

      expect(blocks, hasLength(2));
      expect(blocks[0].blockId, 'b1');
      expect(blocks[0].segments.first.text, 'Hello');
      expect(blocks[1].blockId, 'b2');
      expect(blocks[1].segments.first.text, 'World');
    });

    test('applies BlockInsert to add new block', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'First')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final insertEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [
          const BlockInsert(
            blockId: 'b2',
            afterBlockId: 'b1',
            segments: [TextSegment(text: 'Second')],
          ),
        ],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, insertEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, insertEntry);

      expect(blocks, hasLength(2));
      expect(blocks[0].blockId, 'b1');
      expect(blocks[1].blockId, 'b2');
      expect(blocks[1].segments.first.text, 'Second');
    });

    test('applies BlockDelete to remove block', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'First')],
            ),
            TextBlockSnapshot(
              blockId: 'b2',
              afterBlockId: 'b1',
              segments: [TextSegment(text: 'Second')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final deleteEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [const BlockDelete(blockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, deleteEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, deleteEntry);

      expect(blocks, hasLength(1));
      expect(blocks[0].blockId, 'b2');
    });

    test('applies BlockUpdate to modify block segments', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'Original')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final updateEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [
          const BlockUpdate(
            blockId: 'b1',
            segments: [TextSegment(text: 'Updated')],
          ),
        ],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, updateEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, updateEntry);

      expect(blocks, hasLength(1));
      expect(blocks[0].blockId, 'b1');
      expect(blocks[0].segments.first.text, 'Updated');
    });

    test('applies BlockMove to reorder blocks', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'First')],
            ),
            TextBlockSnapshot(
              blockId: 'b2',
              afterBlockId: 'b1',
              segments: [TextSegment(text: 'Second')],
            ),
            TextBlockSnapshot(
              blockId: 'b3',
              afterBlockId: 'b2',
              segments: [TextSegment(text: 'Third')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final moveEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [const BlockMove(blockId: 'b3', afterBlockId: 'b1')],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, moveEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, moveEntry);

      expect(blocks, hasLength(3));
      expect(blocks[0].blockId, 'b1');
      expect(blocks[1].blockId, 'b3');
      expect(blocks[2].blockId, 'b2');
    });

    test('reconstructs state across multiple devices', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'Original')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final editDev1 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [
          const BlockUpdate(
            blockId: 'b1',
            segments: [TextSegment(text: 'Dev1 edit')],
          ),
        ],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final editDev2 = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('300-0000-dev2'),
        parent: Hlc.fromKey('200-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [
          const BlockInsert(
            blockId: 'b2',
            afterBlockId: 'b1',
            segments: [TextSegment(text: 'Dev2 addition')],
          ),
        ],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev2',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, editDev1],
        'dev2': [editDev2],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, editDev2);

      expect(blocks, hasLength(2));
      expect(blocks[0].segmentText, 'Dev1 edit');
      expect(blocks[1].segmentText, 'Dev2 addition');
    });

    test('BlockInsert with null afterBlockId inserts at beginning', () {
      final createEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('100-0000-dev1'),
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: const FileCreateOp(
          pageId: 'p1',
          initialBlocks: [
            TextBlockSnapshot(
              blockId: 'b1',
              afterBlockId: null,
              segments: [TextSegment(text: 'Original')],
            ),
          ],
        ),
        fileHash: null,
        deviceId: 'dev1',
      );

      final insertEntry = OpLogEntry(
        version: 1,
        hlc: Hlc.fromKey('200-0000-dev1'),
        parent: Hlc.fromKey('100-0000-dev1'),
        parentB: null,
        type: OpEntryType.edit,
        blockOps: [
          const BlockInsert(
            blockId: 'b0',
            afterBlockId: null,
            segments: [TextSegment(text: 'New first')],
          ),
        ],
        fileOp: null,
        fileHash: null,
        deviceId: 'dev1',
      );

      final dag = OpLogDag.fromEntries({
        'dev1': [createEntry, insertEntry],
      });
      final blocks = StateReconstructionEngine.reconstruct(dag, insertEntry);

      expect(blocks, hasLength(2));
      expect(blocks[0].blockId, 'b0');
      expect(blocks[1].blockId, 'b1');
    });
  });
}
