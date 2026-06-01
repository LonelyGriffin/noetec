// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

class DocumentModel {
  final String id;
  final Map<String, Block> _blocks = {};
  final ListNotifier<Block> rootBlocks = ListNotifier(data: []);
  final ValueNotifier<SelectionState> selection = ValueNotifier(NoSelectionState());

  DocumentModel({required this.id});

  Block? getBlockById(String id) => _blocks[id];

  /// Derived notifier: set of block IDs that are currently selected.
  /// Recomputed whenever selection or rootBlocks structure changes.
  /// Triggers only when the set of selected IDs actually changes.
  late final ValueListenable<Set<String>> selectedBlockIds =
    selection.combineLatest<List<Block>, Set<String>>(
      rootBlocks,
      (selState, _) => _computeSelectedIds(selState),
    );
  
  void removeBlock(String blockId) {
    final block = _blocks[blockId];
    if (block == null) return;

    if (block.parent.value == null) {
      rootBlocks.remove(block);
    } else {
      final parent = block.parent.value as ContainerBlock;
      parent.children.remove(block);
    }
    _blocks.remove(blockId);
  }

  void addBlock(Block block, int siblingsIndex) { 
    if (block.parent.value == null) {
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

  /// Computes a [TextEditingValue] from the current selection and block content.
  /// Used by the input layer to synchronize IME state after non-IME actions
  /// (clicks, keyboard navigation, etc.) where no delta.apply() is available.
  TextEditingValue computeTextEditingValue() {
    final sel = selection.value;
    if (sel is SingleCursorSelectionState) {
      final cursor = sel.cursorPos;
      if (cursor is CursorPositionInTextBlock) {
        final block = getBlockById(cursor.blockId);
        if (block is TextBlock) {
          return TextEditingValue(
            text: block.computeAllSegmentsText(),
            selection: TextSelection.collapsed(
              offset: block.flatOffsetFromCursor(cursor.segmentIndex, cursor.offset),
            ),
          );
        }
      }
    }
    return TextEditingValue.empty;
  }

  /// Computes which block IDs are currently selected based on SelectionState.
  Set<String> _computeSelectedIds(SelectionState state) {
    if (state is NoSelectionState) {
      return const {};
    }

    if (state is SingleCursorSelectionState) {
      return {state.cursorPos.blockId};
    }

    if (state is RangeSelectionState) {
      final flat = flatBlockIds();
      final fromIdx = flat.indexOf(state.from.blockId);
      final toIdx = flat.indexOf(state.to.blockId);

      if (fromIdx == -1 || toIdx == -1) {
        return const {};
      }

      final start = fromIdx < toIdx ? fromIdx : toIdx;
      final end = fromIdx < toIdx ? toIdx : fromIdx;

      return flat.sublist(start, end + 1).toSet();
    }

    return {};
  }

  /// Returns a flat, depth-first list of all block IDs in the document tree.
  List<String> flatBlockIds() {
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
}
