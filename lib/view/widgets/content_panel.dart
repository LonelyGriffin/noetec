// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:noetec/view/widgets/content_panel/bookmarks_panel.dart';
import 'package:noetec/view/widgets/content_panel/journal_panel.dart';
import 'package:noetec/view/widgets/content_panel/pages_panel.dart';
import 'package:noetec/view/widgets/content_panel/settings_panel.dart';
import 'package:watch_it/watch_it.dart';

class ContentPanel extends WatchingWidget {
  const ContentPanel({super.key});

  static const double width = 280;

  @override
  Widget build(BuildContext context) {
    final activePanel = watchValue<LayoutUISystem, RailPanel>(
      (s) => s.activePanel,
    );
    final isCollapsed = watchValue<LayoutUISystem, bool>(
      (s) => s.isContentPanelCollapsed,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: isCollapsed ? 0 : width,
      child: isCollapsed ? const SizedBox.shrink() : _panelFor(activePanel),
    );
  }

  Widget _panelFor(RailPanel panel) {
    return switch (panel) {
      RailPanel.journal => const JournalPanel(),
      RailPanel.pages => const PagesPanel(),
      RailPanel.bookmarks => const BookmarksPanel(),
      RailPanel.settings => const SettingsPanel(),
    };
  }
}
