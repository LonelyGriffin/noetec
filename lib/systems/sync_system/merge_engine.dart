// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';

sealed class MergeResult {
  const MergeResult();
}

final class MergeNoop extends MergeResult {
  const MergeNoop();
}

final class MergeFastForward extends MergeResult {
  final List<ReconstructedBlock> updatedBlocks;

  const MergeFastForward({required this.updatedBlocks});
}

final class MergeSuccess extends MergeResult {
  final List<ReconstructedBlock> mergedBlocks;
  final Hlc ourHead;
  final Hlc theirHead;

  const MergeSuccess({
    required this.mergedBlocks,
    required this.ourHead,
    required this.theirHead,
  });
}

final class MergeConflict extends MergeResult {
  final List<BlockConflict> conflicts;
  final List<ReconstructedBlock> partiallyMergedBlocks;
  final Hlc ourHead;
  final Hlc theirHead;

  const MergeConflict({
    required this.conflicts,
    required this.partiallyMergedBlocks,
    required this.ourHead,
    required this.theirHead,
  });
}

sealed class BlockConflict {
  final String blockId;
  const BlockConflict({required this.blockId});
}

final class ContentConflict extends BlockConflict {
  final ReconstructedBlock ours;
  final ReconstructedBlock theirs;

  const ContentConflict({
    required super.blockId,
    required this.ours,
    required this.theirs,
  });
}

final class DeleteModifyConflict extends BlockConflict {
  final ReconstructedBlock modifiedBlock;
  final bool deletedByUs;

  const DeleteModifyConflict({
    required super.blockId,
    required this.modifiedBlock,
    required this.deletedByUs,
  });
}

class MergeEngine {
  const MergeEngine._();

  static MergeResult merge(OpLogDag dag) {
    final heads = dag.heads.values.toList();
    if (heads.length < 2) return const MergeNoop();

    final topology = dag.topology;
    if (topology == DagTopology.empty || topology == DagTopology.single) {
      return const MergeNoop();
    }

    if (topology == DagTopology.linear) {
      final sorted = heads..sort((a, b) => a.hlc.compareTo(b.hlc));
      final latest = sorted.last;
      return MergeFastForward(
        updatedBlocks: StateReconstructionEngine.reconstruct(dag, latest),
      );
    }

    final ourHead = heads.firstWhere((h) => h.deviceId == dag.heads.keys.first);
    final theirHead = heads.firstWhere((h) => h.deviceId != ourHead.deviceId);

    final ancestor = dag.lca(ourHead, theirHead);
    if (ancestor == null) {
      return const MergeNoop();
    }

    final ancestorBlocks = StateReconstructionEngine.reconstruct(dag, ancestor);
    final ourBlocks = StateReconstructionEngine.reconstruct(dag, ourHead);
    final theirBlocks = StateReconstructionEngine.reconstruct(dag, theirHead);

    return _threeWayMerge(
      ancestor: ancestorBlocks,
      ours: ourBlocks,
      theirs: theirBlocks,
      ourHead: ourHead.hlc,
      theirHead: theirHead.hlc,
    );
  }

  static MergeResult _threeWayMerge({
    required List<ReconstructedBlock> ancestor,
    required List<ReconstructedBlock> ours,
    required List<ReconstructedBlock> theirs,
    required Hlc ourHead,
    required Hlc theirHead,
  }) {
    final ancestorMap = {for (final b in ancestor) b.blockId: b};
    final ourMap = {for (final b in ours) b.blockId: b};
    final theirMap = {for (final b in theirs) b.blockId: b};

    final conflicts = <BlockConflict>[];
    final merged = <ReconstructedBlock>[];

    final mergedOrder = _computeMergedOrder(ancestor, ours, theirs);

    for (final orderedBlock in mergedOrder) {
      final blockId = orderedBlock.blockId;
      final inAncestor = ancestorMap[blockId];
      final inOurs = ourMap[blockId];
      final inTheirs = theirMap[blockId];

      final deletedByUs = inOurs == null && inAncestor != null;
      final deletedByThem = inTheirs == null && inAncestor != null;
      final changedByUs =
          inOurs != null &&
          inAncestor != null &&
          !_blocksEqual(inOurs, inAncestor);
      final changedByThem =
          inTheirs != null &&
          inAncestor != null &&
          !_blocksEqual(inTheirs, inAncestor);

      if (deletedByUs && deletedByThem) continue;

      if (deletedByUs && changedByThem) {
        conflicts.add(
          DeleteModifyConflict(
            blockId: blockId,
            modifiedBlock: inTheirs,
            deletedByUs: true,
          ),
        );
        continue;
      }

      if (deletedByThem && changedByUs) {
        conflicts.add(
          DeleteModifyConflict(
            blockId: blockId,
            modifiedBlock: inOurs,
            deletedByUs: false,
          ),
        );
        continue;
      }

      if (deletedByUs || deletedByThem) {
        continue;
      }

      if (inAncestor == null) {
        merged.add(inOurs ?? inTheirs!);
        continue;
      }

      if (changedByUs && changedByThem) {
        if (_blocksEqual(inOurs, inTheirs)) {
          merged.add(inOurs);
        } else {
          conflicts.add(
            ContentConflict(blockId: blockId, ours: inOurs, theirs: inTheirs),
          );
        }
        continue;
      }

      if (changedByUs) {
        merged.add(inOurs);
        continue;
      }

      if (changedByThem) {
        merged.add(inTheirs);
        continue;
      }

      merged.add(inAncestor);
    }

    if (conflicts.isEmpty) {
      return MergeSuccess(
        mergedBlocks: merged,
        ourHead: ourHead,
        theirHead: theirHead,
      );
    }

    return MergeConflict(
      conflicts: conflicts,
      partiallyMergedBlocks: merged,
      ourHead: ourHead,
      theirHead: theirHead,
    );
  }

  static List<ReconstructedBlock> _computeMergedOrder(
    List<ReconstructedBlock> ancestor,
    List<ReconstructedBlock> ours,
    List<ReconstructedBlock> theirs,
  ) {
    final mergedMap = <String, ReconstructedBlock>{};
    for (final b in ancestor) {
      mergedMap[b.blockId] = b;
    }
    for (final b in ours) {
      mergedMap[b.blockId] = b;
    }
    for (final b in theirs) {
      mergedMap[b.blockId] = b;
    }

    final ordered = <ReconstructedBlock>[];
    final seen = <String>{};

    final ancestorIds = {for (final a in ancestor) a.blockId};

    void flushNew(int startIdx, int endIdx, List<ReconstructedBlock> source) {
      for (var i = startIdx; i < endIdx; i++) {
        final b = source[i];
        if (!ancestorIds.contains(b.blockId) && seen.add(b.blockId)) {
          ordered.add(mergedMap[b.blockId]!);
        }
      }
    }

    for (final ancestorBlock in ancestor) {
      final ourPos = ours.indexWhere((b) => b.blockId == ancestorBlock.blockId);
      final theirPos = theirs.indexWhere(
        (b) => b.blockId == ancestorBlock.blockId,
      );

      if (ourPos > 0) flushNew(0, ourPos, ours);
      if (theirPos > 0) flushNew(0, theirPos, theirs);

      if (seen.add(ancestorBlock.blockId)) {
        ordered.add(mergedMap[ancestorBlock.blockId]!);
      }
    }

    for (final b in ours) {
      if (seen.add(b.blockId)) ordered.add(mergedMap[b.blockId]!);
    }
    for (final b in theirs) {
      if (seen.add(b.blockId)) ordered.add(mergedMap[b.blockId]!);
    }

    return ordered;
  }

  static bool _blocksEqual(ReconstructedBlock a, ReconstructedBlock b) {
    if (a.segments.length != b.segments.length) return false;
    for (var i = 0; i < a.segments.length; i++) {
      if (a.segments[i].text != b.segments[i].text) return false;
    }
    return true;
  }
}
