import 'package:flutter/material.dart';
import 'package:noetec/DocumentSystem/document_block.dart';
import 'package:noetec/DocumentSystem/document_model.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/DocumentView/block_selection_info.dart';
import 'package:noetec/DocumentView/text_block_widget.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:watch_it/watch_it.dart';

class DocumentEditorBlockWidget extends StatefulWidget {
  const DocumentEditorBlockWidget({
    super.key,
    required this.block,
    required this.documentId,
  });

  final Block block;
  final String documentId;

  @override
  State<DocumentEditorBlockWidget> createState() =>
      _DocumentEditorBlockWidgetState();
}

class _DocumentEditorBlockWidgetState extends State<DocumentEditorBlockWidget> {
  late DocumentModel _model;
  bool _isSelected = false;

  @override
  void initState() {
    super.initState();
    _model = di<OpenedDocumentsManager>().getDocument(widget.documentId)!;
    _isSelected = _model.selectedBlockIds.value.contains(widget.block.id);
    _model.selectedBlockIds.addListener(_onSelectedBlockIdsChanged);
    _model.selection.addListener(_onSelectionChanged);
  }

  /// Handles changes to the set of selected block IDs.
  /// Triggers a rebuild only when this block's participation in the selection changes.
  void _onSelectedBlockIdsChanged() {
    final nowSelected =
        _model.selectedBlockIds.value.contains(widget.block.id);
    if (nowSelected != _isSelected) {
      setState(() => _isSelected = nowSelected);
    }
  }

  /// Handles changes to the raw selection state.
  /// Triggers a rebuild only when this block is currently selected, so that the
  /// cursor or range position within the block is updated (e.g. clicking a new
  /// position inside the same block does not change selectedBlockIds at all).
  void _onSelectionChanged() {
    final stillSelected =
        _model.selectedBlockIds.value.contains(widget.block.id);
    if (_isSelected && stillSelected) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _model.selectedBlockIds.removeListener(_onSelectedBlockIdsChanged);
    _model.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.block is! TextBlock) return const SizedBox.shrink();

    final textBlock = widget.block as TextBlock;
    final selectionInfo =
        _computeBlockSelectionInfo(textBlock.id, _model.selection.value);
    debugPrint(
      'Building block ${textBlock.id} with selectionInfo $selectionInfo',
    );
    return TextBlockWidget(
      key: Key(textBlock.id),
      block: textBlock,
      selectionInfo: selectionInfo,
      onTextClick: (blockId, segmentIndex, offset) {
        di<UserActionService>().handleAction(
          ClickOnTextBlock(
            documentId: widget.documentId,
            blockId: blockId,
            segmentIndex: segmentIndex,
            offset: offset,
          ),
        );
      },
    );
  }

  /// Computes what role this specific block plays in the current selection.
  /// Returns:
  /// - BlockNotSelected if not in selection
  /// - BlockFullySelected if between two cursors (but doesn't contain either cursor)
  /// - BlockWithCursor if contains exactly one cursor (collapsed or range edge)
  /// - BlockWithRange if contains both cursors (range within single block)
  BlockSelectionInfo _computeBlockSelectionInfo(
    String blockId,
    SelectionState state,
  ) {
    if (state is! TextSelectionState) {
      return BlockNotSelected();
    }

    final fromId = state.from.blockId;
    final toId = state.to.blockId;
    final isCollapsed = state.isCollapsed;

    // Collapsed selection (cursor only) in this block
    if (isCollapsed && fromId == blockId) {
      return BlockWithCursor(
        segmentIndex: state.from.segmentIndex,
        offset: state.from.offset,
      );
    }

    // Range with both cursors in the same block
    if (!isCollapsed && fromId == blockId && toId == blockId) {
      return BlockWithRange(
        fromSegmentIndex: state.from.segmentIndex,
        fromOffset: state.from.offset,
        toSegmentIndex: state.to.segmentIndex,
        toOffset: state.to.offset,
      );
    }

    // Range with 'from' cursor in this block (and 'to' elsewhere)
    if (!isCollapsed && fromId == blockId) {
      return BlockWithCursor(
        segmentIndex: state.from.segmentIndex,
        offset: state.from.offset,
      );
    }

    // Range with 'to' cursor in this block (and 'from' elsewhere)
    if (!isCollapsed && toId == blockId) {
      return BlockWithCursor(
        segmentIndex: state.to.segmentIndex,
        offset: state.to.offset,
      );
    }

    // Block is in the range but doesn't contain either cursor
    // (This is handled implicitly by DocumentModel.selectedBlockIds, but we return BlockFullySelected for rendering)
    if (_model.selectedBlockIds.value.contains(blockId)) {
      return BlockFullySelected();
    }

    // Not in selection
    return BlockNotSelected();
  }
}
