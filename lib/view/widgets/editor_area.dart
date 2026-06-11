// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:watch_it/watch_it.dart';

class EditorArea extends WatchingWidget {
  const EditorArea({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = watchValue<LayoutUISystem, List<EditorTab>>((s) => s.openTabs);
    final activeTabId = watchValue<LayoutUISystem, String?>(
      (s) => s.activeTabId,
    );
    final theme = Theme.of(context);

    return Column(
      children: [
        if (tabs.isNotEmpty)
          _EditorTabBar(tabs: tabs, activeTabId: activeTabId),
        Expanded(
          child: tabs.isEmpty
              ? Center(
                  child: Text(
                    'Open a page to start editing',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _EditorContent(activeTabId: activeTabId, tabs: tabs),
        ),
      ],
    );
  }
}

class _EditorTabBar extends StatelessWidget {
  const _EditorTabBar({required this.tabs, required this.activeTabId});

  final List<EditorTab> tabs;
  final String? activeTabId;

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
        itemCount: tabs.length,
        itemExtent: 160,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.id == activeTabId;

          return Container(
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
                    onTap: () => di<LayoutUISystem>().openTab(tab),
                    child: Text(
                      tab.title,
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
                  onTap: () => di<LayoutUISystem>().closeTab(tab.id),
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
  const _EditorContent({required this.activeTabId, required this.tabs});

  final String? activeTabId;
  final List<EditorTab> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTab = tabs.where((t) => t.id == activeTabId).firstOrNull;

    if (activeTab == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activeTab.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Editor content for "${activeTab.title}" will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
