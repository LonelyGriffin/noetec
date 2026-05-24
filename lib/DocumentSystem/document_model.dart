import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

class DocumentModel {
  final String id;
  final Map<String, Block> _blocks = {};
  final ListNotifier<Block> rootBlocks = ListNotifier(data: []);

  final ValueNotifier<SelectionState> selection =
      ValueNotifier(NoSelectionState());

  /// Derived notifier: set of block IDs that are currently selected.
  /// Recomputed whenever selection or rootBlocks structure changes.
  /// Triggers only when the set of selected IDs actually changes.
  late final ValueListenable<Set<String>> selectedBlockIds =
      selection.combineLatest<List<Block>, Set<String>>(
        rootBlocks,
        (selState, _) => _computeSelectedIds(selState),
      );

  Block? getBlockById(String id) => _blocks[id];

  /// Returns the index of [blockId] within [rootBlocks], or -1 if not found.
  /// Only searches top-level blocks (not nested containers).
  int getBlockIndex(String blockId) {
    final blocks = rootBlocks.value;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].id == blockId) return i;
    }
    return -1;
  }

  DocumentModel({required this.id});

  void addBlock(Block block, int siblingsIndex) {
    if (block.parent.value == null) {
      // its a root block
      rootBlocks.insert(siblingsIndex, block);
    } else {
      final parentBlock = _blocks[block.parent.value!.id];
      if (parentBlock == null) {
        throw ArgumentError(
          'Parent block with id ${block.parent.value!.id} does not exist',
        );
      }
      if (parentBlock is! ContainerBlock) {
        throw ArgumentError(
          'Parent block with id ${block.parent.value!.id} is not a container block',
        );
      }
      parentBlock.children.insert(siblingsIndex, block);
    }
    _blocks[block.id] = block;
  }

  /// Returns a flat, depth-first list of all block IDs in the document tree.
  /// Used to compute range selections between blocks.
  List<String> _flatBlockIds() {
    final result = <String>[];
    void visit(Block b) {
      result.add(b.id);
      if (b is ContainerBlock) {
        for (final child in b.children.value) {
          visit(child);
        }
      }
    }
    for (final b in rootBlocks.value) {
      visit(b);
    }
    return result;
  }

  /// Computes which block IDs are currently selected based on SelectionState.
  /// Returns:
  /// - Empty set if no selection (NoSelectionState)
  /// - Set of all IDs from first selected block to last selected block (inclusive)
  /// For collapsed selections, returns just the block ID containing the cursor.
  Set<String> _computeSelectedIds(SelectionState state) {
    if (state is! TextSelectionState) {
      return const {};
    }

    final fromId = state.from.blockId;
    final toId = state.to.blockId;

    // Single block selection
    if (fromId == toId) {
      return {fromId};
    }

    // Range across multiple blocks
    final flat = _flatBlockIds();
    final fromIdx = flat.indexOf(fromId);
    final toIdx = flat.indexOf(toId);

    if (fromIdx == -1 || toIdx == -1) {
      return const {};
    }

    final start = fromIdx < toIdx ? fromIdx : toIdx;
    final end = fromIdx < toIdx ? toIdx : fromIdx;

    return flat.sublist(start, end + 1).toSet();
  }
}
