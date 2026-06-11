// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:watch_it/watch_it.dart';

class PagesPanel extends StatelessWidget {
  const PagesPanel({super.key});

  static const _stubTree = [
    _PageNode(
      id: 'page-root-1',
      title: 'Getting Started',
      children: [
        _PageNode(id: 'page-1-1', title: 'Installation'),
        _PageNode(id: 'page-1-2', title: 'Configuration'),
      ],
    ),
    _PageNode(
      id: 'page-root-2',
      title: 'Project Notes',
      children: [
        _PageNode(
          id: 'page-2-1',
          title: 'Architecture',
          children: [
            _PageNode(id: 'page-2-1-1', title: 'Overview'),
            _PageNode(id: 'page-2-1-2', title: 'Decisions'),
          ],
        ),
        _PageNode(id: 'page-2-2', title: 'Roadmap'),
      ],
    ),
    _PageNode(id: 'page-root-3', title: 'Daily Journal'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Pages',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final node in _stubTree) _TreeNode(node: node, depth: 0),
            ],
          ),
        ),
      ],
    );
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({required this.node, required this.depth});

  final _PageNode node;
  final int depth;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (hasChildren) {
              setState(() => _expanded = !_expanded);
            }
            if (!hasChildren) {
              di<LayoutUISystem>().openTab(
                EditorTab(id: widget.node.id, title: widget.node.title),
              );
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 8.0 + widget.depth * 16.0,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                if (hasChildren)
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 4),
                Icon(
                  hasChildren ? Icons.folder_outlined : Icons.article_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.node.title,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          ...widget.node.children.map(
            (child) => _TreeNode(node: child, depth: widget.depth + 1),
          ),
      ],
    );
  }
}

final class _PageNode {
  const _PageNode({
    required this.id,
    required this.title,
    this.children = const [],
  });

  final String id;
  final String title;
  final List<_PageNode> children;
}
