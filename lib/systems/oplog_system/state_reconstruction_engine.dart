// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

class ReconstructedBlock {
  final String blockId;
  final List<TextSegment> segments;

  const ReconstructedBlock({required this.blockId, required this.segments});

  String get segmentText => segments.map((s) => s.text).join();
}

class StateReconstructionEngine {
  const StateReconstructionEngine._();

  static List<ReconstructedBlock> reconstruct(
    OpLogDag dag,
    OpLogEntry targetEntry,
  ) {
    final path = _collectAncestors(dag, targetEntry);
    var state = <ReconstructedBlock>[];
    for (final entry in path) {
      state = _applyEntry(state, entry);
    }
    return state;
  }

  static List<ReconstructedBlock> applyDiff(
    List<ReconstructedBlock> blocks,
    List<BlockOp> ops,
  ) {
    var result = blocks;
    for (final op in ops) {
      result = _applyBlockOp(result, op);
    }
    return result;
  }

  static List<ReconstructedBlock> applyBlockOp(
    List<ReconstructedBlock> blocks,
    BlockOp op,
  ) => _applyBlockOp(blocks, op);

  static List<ReconstructedBlock> _applyEntry(
    List<ReconstructedBlock> state,
    OpLogEntry entry,
  ) {
    var result = state;
    switch (entry.type) {
      case OpEntryType.fileCreate:
        final fileOp = entry.fileOp;
        if (fileOp is FileCreateOp) {
          for (final snapshot in fileOp.initialBlocks) {
            result = _applyBlockOp(
              result,
              BlockInsert(
                blockId: snapshot.blockId,
                afterBlockId: snapshot.afterBlockId,
                segments: snapshot.segments,
              ),
            );
          }
        }
      case OpEntryType.edit:
      case OpEntryType.externalEdit:
        for (final op in entry.blockOps ?? const <BlockOp>[]) {
          result = _applyBlockOp(result, op);
        }
      case OpEntryType.fileDelete:
      case OpEntryType.fileRename:
      case OpEntryType.save:
      case OpEntryType.merge:
        break;
    }
    return result;
  }

  static List<ReconstructedBlock> _applyBlockOp(
    List<ReconstructedBlock> blocks,
    BlockOp op,
  ) {
    final result = List<ReconstructedBlock>.of(blocks);

    switch (op) {
      case BlockInsert():
        final block = ReconstructedBlock(
          blockId: op.blockId,
          segments: List.of(op.segments),
        );
        _insertAfter(result, block, op.afterBlockId);

      case BlockDelete():
        result.removeWhere((b) => b.blockId == op.blockId);

      case BlockUpdate():
        final index = result.indexWhere((b) => b.blockId == op.blockId);
        if (index != -1) {
          result[index] = ReconstructedBlock(
            blockId: op.blockId,
            segments: List.of(op.segments),
          );
        }

      case BlockMove():
        final index = result.indexWhere((b) => b.blockId == op.blockId);
        if (index != -1) {
          final block = result.removeAt(index);
          _insertAfter(result, block, op.afterBlockId);
        }
    }

    return result;
  }

  static void _insertAfter(
    List<ReconstructedBlock> blocks,
    ReconstructedBlock block,
    String? afterBlockId,
  ) {
    if (afterBlockId == null) {
      blocks.insert(0, block);
      return;
    }
    final index = blocks.indexWhere((b) => b.blockId == afterBlockId);
    if (index == -1) {
      blocks.add(block);
    } else {
      blocks.insert(index + 1, block);
    }
  }

  static List<OpLogEntry> _collectAncestors(OpLogDag dag, OpLogEntry target) {
    final visited = <String, OpLogEntry>{};
    final stack = <OpLogEntry>[target];

    while (stack.isNotEmpty) {
      final entry = stack.removeLast();
      final key = entry.hlcKey;
      if (visited.containsKey(key)) continue;
      visited[key] = entry;

      final parent = entry.parent;
      if (parent != null) {
        final p = dag.entriesByHlc[parent.toKey()];
        if (p != null) stack.add(p);
      }
      final parentB = entry.parentB;
      if (parentB != null) {
        final pb = dag.entriesByHlc[parentB.toKey()];
        if (pb != null) stack.add(pb);
      }
    }

    final ordered = visited.values.toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));
    return ordered;
  }
}
