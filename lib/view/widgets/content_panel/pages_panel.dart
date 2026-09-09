// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noetec/service/rename_controller.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:watch_it/watch_it.dart';

class PagesPanel extends WatchingWidget {
  const PagesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = watchValue<VaultFileService, List<PageFileNode>>((s) => s.fileTree);
    final vaultFileService = di<VaultFileService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Pages', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(icon: const Icon(Icons.add, size: 18), tooltip: 'New Page', onPressed: () => _createPage(vaultFileService)),
            ],
          ),
        ),
        Expanded(
          child: tree.isEmpty
              ? Center(
                  child: Text('No pages yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [for (final node in tree) _TreeNode(node: node, depth: 0)],
                ),
        ),
      ],
    );
  }

  Future<void> _createPage(VaultFileService vaultFileService) async {
    final vault = di<VaultSystem>().currentVault.value;
    if (vault == null) return;

    final relativePath = await vaultFileService.createPage(vault.rootPath);
    di<RenameController>().beginCommand.run(relativePath);
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({required this.node, required this.depth});

  final PageFileNode node;
  final int depth;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isFolder = node is PageFileFolder;
    final children = isFolder ? node.children : <PageFileNode>[];
    final hasChildren = children.isNotEmpty;
    final theme = Theme.of(context);
    final vaultFileService = di<VaultFileService>();
    final renameController = di<RenameController>();

    return ListenableBuilder(
      listenable: Listenable.merge([renameController.activePath, vaultFileService.selectedPagePath]),
      builder: (context, _) {
        final isRenaming = node is PageFileItem && renameController.activePath.value == node.relativePath;
        final isSelected = node is PageFileItem && vaultFileService.selectedPagePath.value == node.relativePath;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _handleTap(isFolder, hasChildren, node),
              child: Container(
                decoration: BoxDecoration(color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null, borderRadius: BorderRadius.circular(6)),
                padding: EdgeInsets.only(left: 8.0 + widget.depth * 16.0, right: 8, top: 4, bottom: 4),
                child: Row(
                  children: [
                    if (isFolder) Icon(_expanded ? Icons.expand_more : Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant) else const SizedBox(width: 18),
                    const SizedBox(width: 4),
                    Icon(isFolder ? Icons.folder_outlined : Icons.article_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: isRenaming ? _RenameField(node: node) : Text(node.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
            if (isFolder && hasChildren && _expanded) ...children.map((child) => _TreeNode(node: child, depth: widget.depth + 1)),
          ],
        );
      },
    );
  }

  void _handleTap(bool isFolder, bool hasChildren, PageFileNode node) {
    final vaultFileService = di<VaultFileService>();

    if (isFolder && hasChildren) {
      setState(() => _expanded = !_expanded);
    }
    if (node is PageFileItem) {
      final isSecondTap = vaultFileService.selectedPagePath.value == node.relativePath;
      vaultFileService.selectedPagePath.value = node.relativePath;

      if (isSecondTap) {
        di<RenameController>().beginCommand.run(node.relativePath);
      } else {
        _openPage(node);
      }
    } else {
      vaultFileService.selectedPagePath.value = null;
    }
  }

  Future<void> _openPage(PageFileItem item) async {
    await di<PageSystem>().loadPage(item.relativePath);
  }
}

class _RenameField extends StatefulWidget {
  const _RenameField({required this.node});

  final PageFileItem node;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final RenameController _rename;

  @override
  void initState() {
    super.initState();
    _rename = di<RenameController>();
    final nameWithoutExt = widget.node.name.endsWith('.md') ? widget.node.name.substring(0, widget.node.name.length - 3) : widget.node.name;
    _controller = TextEditingController(text: nameWithoutExt);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _onCommit();
    }
  }

  /// Reports the "commit" intent to the [RenameController].
  ///
  /// Both Enter ([TextField.onSubmitted]) and focus-loss funnel through here,
  /// and the controller guarantees the rename runs at most once per session —
  /// the second call observes a non-`editing` phase and is a no-op. This view
  /// no longer calls `renamePage` or touches `renamingPath` itself.
  void _onCommit() {
    _rename.confirmCommand.run(_controller.text);
  }

  /// Reports the "cancel" intent (Escape) to the [RenameController].
  void _onCancel() {
    _rename.cancelCommand.run();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _onCancel();
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 4), border: InputBorder.none),
        style: Theme.of(context).textTheme.bodyMedium,
        onSubmitted: (_) => _onCommit(),
      ),
    );
  }
}
