// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';
import 'package:noetec/systems/sync_system/conflict_store.dart';
import 'package:noetec/systems/sync_system/merge_engine.dart';

enum ConflictResolution {
  keepOurs,
  keepTheirs,
  keepBoth,
  acceptDelete,
  keepModified,
}

class ConflictResolver {
  ConflictResolver({
    required ConflictStore conflictStore,
    required String vaultRootPath,
  }) : _conflictStore = conflictStore,
       _vaultRootPath = vaultRootPath;

  final ConflictStore _conflictStore;
  final String _vaultRootPath;

  String get vaultRootPath => _vaultRootPath;

  ({List<ReconstructedBlock> resolvedBlocks, bool allResolved})?
  resolveConflict(
    String relativePath,
    List<ReconstructedBlock> currentBlocks,
    BlockConflict conflict,
    ConflictResolution resolution,
  ) {
    final result = List<ReconstructedBlock>.of(currentBlocks);
    final blockId = conflict.blockId;

    switch (conflict) {
      case ContentConflict():
        _resolveContentConflict(result, conflict, resolution);
      case DeleteModifyConflict():
        _resolveDeleteModifyConflict(result, conflict, resolution);
    }

    _conflictStore.removeBlockConflict(relativePath, blockId);
    final entry = _conflictStore.getByPath(relativePath);
    final allResolved = entry == null;

    return (resolvedBlocks: result, allResolved: allResolved);
  }

  void _resolveContentConflict(
    List<ReconstructedBlock> blocks,
    ContentConflict conflict,
    ConflictResolution resolution,
  ) {
    final idx = blocks.indexWhere((b) => b.blockId == conflict.blockId);
    switch (resolution) {
      case ConflictResolution.keepOurs:
        if (idx != -1) blocks[idx] = conflict.ours;
      case ConflictResolution.keepTheirs:
        if (idx != -1) blocks[idx] = conflict.theirs;
      case ConflictResolution.keepBoth:
        if (idx != -1) {
          final merged = ReconstructedBlock(
            blockId: conflict.blockId,
            segments: [
              ...conflict.ours.segments,
              const TextSegment(text: '\n'),
              ...conflict.theirs.segments,
            ],
          );
          blocks[idx] = merged;
        }
      case ConflictResolution.acceptDelete:
        blocks.removeWhere((b) => b.blockId == conflict.blockId);
      case ConflictResolution.keepModified:
        break;
    }
  }

  void _resolveDeleteModifyConflict(
    List<ReconstructedBlock> blocks,
    DeleteModifyConflict conflict,
    ConflictResolution resolution,
  ) {
    final exists = blocks.any((b) => b.blockId == conflict.blockId);
    switch (resolution) {
      case ConflictResolution.keepModified:
        if (!exists) {
          blocks.add(conflict.modifiedBlock);
        } else {
          final idx = blocks.indexWhere((b) => b.blockId == conflict.blockId);
          if (idx != -1) blocks[idx] = conflict.modifiedBlock;
        }
      case ConflictResolution.acceptDelete:
        blocks.removeWhere((b) => b.blockId == conflict.blockId);
      case ConflictResolution.keepOurs:
        if (conflict.deletedByUs) {
          blocks.removeWhere((b) => b.blockId == conflict.blockId);
        } else if (!exists) {
          blocks.add(conflict.modifiedBlock);
        }
      case ConflictResolution.keepTheirs:
        if (!conflict.deletedByUs) {
          blocks.removeWhere((b) => b.blockId == conflict.blockId);
        } else if (!exists) {
          blocks.add(conflict.modifiedBlock);
        }
      case ConflictResolution.keepBoth:
        if (!exists) blocks.add(conflict.modifiedBlock);
    }
  }
}
