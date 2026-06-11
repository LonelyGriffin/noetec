// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/page/block/block.dart';

/// Make it mutable for performance reasons, unlike other entities.
class PageEntity {
  final String id;
  final Map<String, BlockEntity> blocks = {};
  final List<BlockEntity> rootBlocks = [];

  PageEntity({required this.id});

  BlockEntity? getBlockById(String id) => blocks[id];

  /// Remove block and childs
  void removeBlock(String blockId) {
    final block = blocks[blockId];
    if (block == null) return;

    if (block.parentId == null) {
      rootBlocks.remove(block);
    } else {
      final parent = blocks[block.parentId];
      if (parent != null) {
        parent.children.remove(block);
      }
    }
    for (var i = block.children.length - 1; i >= 0; i--) {
      removeBlock(block.children[i].id);
    }
    blocks.remove(blockId);
  }

  /// Add block after other in document
  /// If [afterBlockId] is null block will be added as first in root
  void addBlock(BlockEntity block, String? afterBlockId) {
    if (block.parentId == null) {
      if (afterBlockId == null) {
        rootBlocks.insert(0, block);
      } else {
        final index = rootBlocks.indexWhere((b) => b.id == afterBlockId);
        if (index != -1) {
          rootBlocks.insert(index + 1, block);
        } else {
          rootBlocks.add(block);
        }
      }
    } else {
      final parentBlock = blocks[block.parentId];
      if (parentBlock == null) {
        throw ArgumentError(
          'Parent block with id ${block.parentId} does not exist',
        );
      }
      if (afterBlockId == null) {
        parentBlock.children.insert(0, block);
      } else {
        final index = parentBlock.children.indexWhere(
          (b) => b.id == afterBlockId,
        );
        if (index != -1) {
          parentBlock.children.insert(index + 1, block);
        } else {
          parentBlock.children.add(block);
        }
      }
    }
    blocks[block.id] = block;
  }

  /// Returns a flat, depth-first list of all block IDs in the document tree.
  List<String> flatBlockIds() {
    final result = <String>[];
    void visit(BlockEntity b) {
      result.add(b.id);
      for (final child in b.children) {
        visit(child);
      }
    }

    for (final b in rootBlocks) {
      visit(b);
    }
    return result;
  }
}
