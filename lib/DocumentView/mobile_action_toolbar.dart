// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';
import 'package:noetec/InputModeService/input_mode_service.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';
import 'package:watch_it/watch_it.dart';

/// A toolbar displayed above the virtual keyboard on touch devices.
///
/// Shows context-sensitive buttons for clipboard operations and selection.
/// Buttons use a single capital letter as label (icons will be added later).
///
/// Visibility rules:
///   - Hidden in mouse mode.
///   - In touch mode: always visible when the editor has focus (Paste is
///     always available; Copy/Cut/SelectAll appear when there is a range
///     selection).
class MobileActionToolbar extends WatchingStatefulWidget {
  const MobileActionToolbar({
    super.key,
    required this.documentId,
    required this.focusNode,
  });

  final String documentId;

  /// The editor's [FocusNode] — the toolbar is shown only when the editor
  /// has focus.
  final FocusNode focusNode;

  @override
  State<MobileActionToolbar> createState() => _MobileActionToolbarState();
}

class _MobileActionToolbarState extends State<MobileActionToolbar> {
  UserInputService get _inputService => di<UserInputService>();
  InputModeService get _inputModeService => di<InputModeService>();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    _inputModeService.mode.addListener(_onModeChanged);

    final doc = di<OpenedDocumentsManager>().getDocument(widget.documentId);
    doc?.selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _inputModeService.mode.removeListener(_onModeChanged);

    final doc = di<OpenedDocumentsManager>().getDocument(widget.documentId);
    doc?.selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});
  void _onModeChanged() => setState(() {});
  void _onSelectionChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Hidden in mouse mode or when the editor does not have focus.
    if (_inputModeService.mode.value != InputMode.touch) {
      return const SizedBox.shrink();
    }
    if (!widget.focusNode.hasFocus) {
      return const SizedBox.shrink();
    }

    final doc = di<OpenedDocumentsManager>().getDocument(widget.documentId);
    final hasRange = doc != null && doc.selection.value is RangeSelectionState;

    return Container(
      width: double.infinity,
      height: 44,
      color: const Color(0xFFF0F0F0),
      child: Row(
        children: [
          if (hasRange) ...[
            _ToolbarButton(
              label: 'A',
              onPressed: () => _inputService.handleSelectAll(widget.documentId),
            ),
            _ToolbarButton(
              label: 'C',
              onPressed: () => _inputService.handleCopy(widget.documentId),
            ),
            _ToolbarButton(
              label: 'X',
              onPressed: () => _inputService.handleCut(widget.documentId),
            ),
          ],
          _ToolbarButton(
            label: 'V',
            onPressed: () => _inputService.handlePaste(widget.documentId),
          ),
        ],
      ),
    );
  }
}

/// A compact toolbar button showing a single capital letter.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}
