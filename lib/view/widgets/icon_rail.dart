// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/app/app_shell.dart';

class IconRail extends StatelessWidget {
  const IconRail({
    super.key,
    required this.activePanel,
    required this.onSelectPanel,
  });

  final RailPanel activePanel;
  final ValueChanged<RailPanel> onSelectPanel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _RailIconButton(
                  icon: Icons.book_outlined,
                  label: 'Journal',
                  isActive: activePanel == RailPanel.journal,
                  onTap: () => onSelectPanel(RailPanel.journal),
                ),
                const SizedBox(height: 8),
                _RailIconButton(
                  icon: Icons.article_outlined,
                  label: 'Pages',
                  isActive: activePanel == RailPanel.pages,
                  onTap: () => onSelectPanel(RailPanel.pages),
                ),
                const SizedBox(height: 8),
                _RailIconButton(
                  icon: Icons.bookmark_outline,
                  label: 'Bookmarks',
                  isActive: activePanel == RailPanel.bookmarks,
                  onTap: () => onSelectPanel(RailPanel.bookmarks),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RailIconButton(
              icon: Icons.settings_outlined,
              label: 'Settings',
              isActive: activePanel == RailPanel.settings,
              onTap: () => onSelectPanel(RailPanel.settings),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive ? activeColor.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isActive ? activeColor : inactiveColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}
