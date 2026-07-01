// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/page/block/block.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:path/path.dart' as p;

class PageEntity {
  final String id;
  final String relativePath;
  final Map<String, BlockEntity> blocks = {};
  final List<BlockEntity> rootBlocks = [];
  final ValueNotifier<SelectionEntity> selection = ValueNotifier(
    const NoSelectionEntity(),
  );

  PageEntity({required this.id, required this.relativePath});

  String get title => p.basenameWithoutExtension(relativePath);

  BlockEntity? getBlockById(String blockId) => blocks[blockId];

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

  void addBlockAt(BlockEntity block, int index) {
    if (block.parentId == null) {
      final clamped = index.clamp(0, rootBlocks.length);
      rootBlocks.insert(clamped, block);
    } else {
      final parentBlock = blocks[block.parentId];
      if (parentBlock == null) {
        throw ArgumentError(
          'Parent block with id ${block.parentId} does not exist',
        );
      }
      final clamped = index.clamp(0, parentBlock.children.length);
      parentBlock.children.insert(clamped, block);
    }
    blocks[block.id] = block;
  }

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

  void dispose() {
    selection.dispose();
    for (final block in blocks.values) {
      block.dispose();
    }
  }
}
