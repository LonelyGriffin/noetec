// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:watch_it/watch_it.dart';

class BookmarksPanel extends StatelessWidget {
  const BookmarksPanel({super.key});

  static const _stubBookmarks = [
    (id: 'bm-1', title: 'Architecture Overview'),
    (id: 'bm-2', title: 'API Reference'),
    (id: 'bm-3', title: 'Design Patterns'),
    (id: 'bm-4', title: 'Deployment Guide'),
    (id: 'bm-5', title: 'Troubleshooting'),
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
            'Bookmarks',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final bookmark in _stubBookmarks)
                ListTile(
                  leading: Icon(
                    Icons.bookmark,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  title: Text(bookmark.title),
                  dense: true,
                  onTap: () => di<LayoutUISystem>().openTab(
                    EditorTab(id: bookmark.id, title: bookmark.title),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
