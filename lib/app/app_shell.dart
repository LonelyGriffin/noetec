// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:noetec/view/widgets/content_panel.dart';
import 'package:noetec/view/widgets/content_panel/bookmarks_panel.dart';
import 'package:noetec/view/widgets/content_panel/journal_panel.dart';
import 'package:noetec/view/widgets/content_panel/pages_panel.dart';
import 'package:noetec/view/widgets/content_panel/settings_panel.dart';
import 'package:noetec/view/widgets/editor_area.dart';
import 'package:noetec/view/widgets/icon_rail.dart';
import 'package:watch_it/watch_it.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const double _breakpoint = 720;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _breakpoint;

    if (isDesktop) {
      return const _DesktopShell();
    }

    return const _MobileShell();
  }
}

class _DesktopShell extends WatchingWidget {
  const _DesktopShell();

  @override
  Widget build(BuildContext context) {
    final isCollapsed = watchValue<LayoutUISystem, bool>(
      (s) => s.isContentPanelCollapsed,
    );

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const IconRail(),
            const VerticalDivider(thickness: 1, width: 1),
            const ContentPanel(),
            if (!isCollapsed) const VerticalDivider(thickness: 1, width: 1),
            const Expanded(child: EditorArea()),
          ],
        ),
      ),
    );
  }
}

class _MobileShell extends WatchingWidget {
  const _MobileShell();

  @override
  Widget build(BuildContext context) {
    final activePanel = watchValue<LayoutUISystem, RailPanel>(
      (s) => s.activePanel,
    );

    return Scaffold(
      body: const EditorArea(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _panelIndex(activePanel),
        onDestinationSelected: (index) {
          final panel = _panelAtIndex(index);
          di<LayoutUISystem>().selectPanel(panel);
          _showPanelSheet(context, panel);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Pages',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Bookmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  static int _panelIndex(RailPanel panel) {
    return switch (panel) {
      RailPanel.journal => 0,
      RailPanel.pages => 1,
      RailPanel.bookmarks => 2,
      RailPanel.settings => 3,
    };
  }

  static RailPanel _panelAtIndex(int index) {
    return switch (index) {
      0 => RailPanel.journal,
      1 => RailPanel.pages,
      2 => RailPanel.bookmarks,
      _ => RailPanel.settings,
    };
  }

  void _showPanelSheet(BuildContext context, RailPanel panel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _panelWidget(panel);
          },
        );
      },
    );
  }

  Widget _panelWidget(RailPanel panel) {
    return switch (panel) {
      RailPanel.journal => const JournalPanel(),
      RailPanel.pages => const PagesPanel(),
      RailPanel.bookmarks => const BookmarksPanel(),
      RailPanel.settings => const SettingsPanel(),
    };
  }
}
