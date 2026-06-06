// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/entity/vault/vault.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:watch_it/watch_it.dart';

class EditorScreen extends WatchingWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = watchValue<VaultSystem, VaultEntity?>((s) => s.currentVault);

    return Scaffold(
      appBar: AppBar(
        title: Text(vault?.name ?? 'Unknown Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Close Vault',
            onPressed: () => di<VaultSystem>().closeVaultCommand.run(),
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Editor — ${vault?.name}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
