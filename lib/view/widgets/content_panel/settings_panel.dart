// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:watch_it/watch_it.dart';

class SettingsPanel extends WatchingWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => di<VaultSystem>().closeVaultCommand.run(),
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Another Vault'),
          ),
        ],
      ),
    );
  }
}
