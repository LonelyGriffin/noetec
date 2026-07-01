// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/app/app_shell.dart';
import 'package:noetec/view/widgets/content_panel/bookmarks_panel.dart';
import 'package:noetec/view/widgets/content_panel/journal_panel.dart';
import 'package:noetec/view/widgets/content_panel/pages_panel.dart';
import 'package:noetec/view/widgets/content_panel/settings_panel.dart';

class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.activePanel,
    required this.isCollapsed,
  });

  static const double width = 280;

  final RailPanel activePanel;
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
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
