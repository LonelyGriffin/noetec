// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';

class BookmarksPanel extends StatelessWidget {
  const BookmarksPanel({super.key});

  static const _stubBookmarks = [
    (title: 'Architecture Overview'),
    (title: 'API Reference'),
    (title: 'Design Patterns'),
    (title: 'Deployment Guide'),
    (title: 'Troubleshooting'),
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
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(bookmark.title),
                  dense: true,
                  enabled: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
