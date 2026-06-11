// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:listen_it/listen_it.dart';

enum RailPanel { journal, pages, bookmarks, settings }

final class EditorTab {
  const EditorTab({required this.id, required this.title});

  final String id;
  final String title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EditorTab && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

class LayoutUISystem {
  final activePanel = CustomValueNotifier<RailPanel>(RailPanel.pages);
  final openTabs = ListNotifier<EditorTab>();
  final activeTabId = CustomValueNotifier<String?>(null);
  final isContentPanelCollapsed = CustomValueNotifier<bool>(false);

  void selectPanel(RailPanel panel) {
    activePanel.value = panel;
  }

  void toggleContentPanel() {
    isContentPanelCollapsed.value = !isContentPanelCollapsed.value;
  }

  void openTab(EditorTab tab) {
    final existing = openTabs.indexWhere((t) => t.id == tab.id);
    if (existing >= 0) {
      activeTabId.value = tab.id;
    } else {
      openTabs.add(tab);
      activeTabId.value = tab.id;
    }
  }

  void closeTab(String tabId) {
    final index = openTabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;

    openTabs.removeAt(index);

    if (activeTabId.value == tabId) {
      if (openTabs.isEmpty) {
        activeTabId.value = null;
      } else {
        final newIndex = index.clamp(0, openTabs.length - 1);
        activeTabId.value = openTabs[newIndex].id;
      }
    }
  }

  void dispose() {
    activePanel.dispose();
    openTabs.dispose();
    activeTabId.dispose();
    isContentPanelCollapsed.dispose();
  }
}
