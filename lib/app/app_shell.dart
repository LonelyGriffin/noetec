// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/view/widgets/content_panel.dart';
import 'package:noetec/view/widgets/content_panel/bookmarks_panel.dart';
import 'package:noetec/view/widgets/content_panel/journal_panel.dart';
import 'package:noetec/view/widgets/content_panel/pages_panel.dart';
import 'package:noetec/view/widgets/content_panel/settings_panel.dart';
import 'package:noetec/view/widgets/editor_area.dart';
import 'package:noetec/view/widgets/icon_rail.dart';

enum RailPanel { journal, pages, bookmarks, settings }

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

class _DesktopShell extends StatefulWidget {
  const _DesktopShell();

  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell> {
  RailPanel _activePanel = RailPanel.pages;
  bool _isContentPanelCollapsed = false;

  void _selectPanel(RailPanel panel) {
    setState(() => _activePanel = panel);
  }

  // ignore: unused_element
  void _toggleCollapsed() {
    setState(() => _isContentPanelCollapsed = !_isContentPanelCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            IconRail(activePanel: _activePanel, onSelectPanel: _selectPanel),
            const VerticalDivider(thickness: 1, width: 1),
            ContentPanel(
              activePanel: _activePanel,
              isCollapsed: _isContentPanelCollapsed,
            ),
            if (!_isContentPanelCollapsed)
              const VerticalDivider(thickness: 1, width: 1),
            const Expanded(child: EditorArea()),
          ],
        ),
      ),
    );
  }
}

class _MobileShell extends StatefulWidget {
  const _MobileShell();

  @override
  State<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<_MobileShell> {
  RailPanel _activePanel = RailPanel.pages;

  void _selectPanel(RailPanel panel) {
    setState(() => _activePanel = panel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const EditorArea(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _panelIndex(_activePanel),
        onDestinationSelected: (index) {
          final panel = _panelAtIndex(index);
          _selectPanel(panel);
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
