// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/view/widgets/editor/page_editor_widget.dart';
import 'package:watch_it/watch_it.dart';

class EditorArea extends WatchingWidget {
  const EditorArea({super.key});

  @override
  Widget build(BuildContext context) {
    final pageSystem = di<PageSystem>();
    final pages = pageSystem.openPages.values.toList();
    final activePageId = watchValue<PageSystem, String?>((s) => s.activePageId);
    final theme = Theme.of(context);

    return Column(
      children: [
        if (pages.isNotEmpty)
          _EditorTabBar(pages: pages, activePageId: activePageId),
        Expanded(
          child: pages.isEmpty
              ? Center(
                  child: Text(
                    'Open a page to start editing',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _EditorContent(activePageId: activePageId, pages: pages),
        ),
      ],
    );
  }
}

class _EditorTabBar extends StatelessWidget {
  const _EditorTabBar({required this.pages, required this.activePageId});

  final List<PageEntity> pages;
  final String? activePageId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: pages.length,
        itemExtent: 160,
        itemBuilder: (context, index) {
          final page = pages[index];
          final isActive = page.id == activePageId;

          return Container(
            key: Key('tab-${page.title}'),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor)),
              color: isActive
                  ? theme.colorScheme.surface
                  : theme.colorScheme.surfaceContainerLowest,
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => di<PageSystem>().setActivePage(page.id),
                    child: Text(
                      page.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: isActive ? FontWeight.w600 : null,
                        color: isActive
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => di<PageSystem>().closePage(page.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EditorContent extends StatelessWidget {
  const _EditorContent({required this.activePageId, required this.pages});

  final String? activePageId;
  final List<PageEntity> pages;

  @override
  Widget build(BuildContext context) {
    final activePage = pages.where((p) => p.id == activePageId).firstOrNull;

    if (activePage == null) {
      return const SizedBox.shrink();
    }

    return PageEditorWidget(pageId: activePage.id);
  }
}
