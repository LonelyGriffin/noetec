// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:command_it/command_it.dart';
import 'package:flutter/material.dart';
import 'package:noetec/entity/vault/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:watch_it/watch_it.dart';

class WelcomeScreen extends WatchingWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vaults = watchValue<VaultSystem, List<VaultEntity>>(
      (s) => s.recentVaults,
    );
    final isCreating = watchValue<VaultSystem, bool>(
      (s) => s.createVaultCommand.isRunning,
    );
    final isOpening = watchValue<VaultSystem, bool>(
      (s) => s.openVaultCommand.isRunning,
    );

    registerHandler<VaultSystem, CommandError?>(
      select: (s) => s.createVaultCommand.errors,
      handler: (context, error, cancel) {
        if (error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.error.toString())));
        }
      },
    );

    registerHandler<VaultSystem, CommandError?>(
      select: (s) => s.openVaultCommand.errors,
      handler: (context, error, cancel) {
        if (error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.error.toString())));
        }
      },
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Text(
                'Noetec',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your local-first note vault',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Expanded(
                child: vaults.isEmpty
                    ? const Center(child: Text('No recent vaults'))
                    : ListView.builder(
                        itemCount: vaults.length,
                        itemBuilder: (context, index) {
                          final vault = vaults[index];
                          return ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(vault.name),
                            subtitle: Text(vault.rootPath),
                            onTap: () => di<VaultSystem>().openVaultCommand.run(
                              vault.rootPath,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isOpening ? null : _pickAndOpen,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open Vault'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isCreating
                          ? null
                          : () => _handleCreate(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Vault'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCreate(BuildContext context) async {
    final pickedPath = await di<IFileSystemService>().pickDirectory();
    if (pickedPath == null) return;
    // ignore: use_build_context_synchronously
    final vaultName = await _showVaultNameDialog(context, pickedPath);
    if (vaultName == null || vaultName.trim().isEmpty) return;
    di<VaultSystem>().createVaultCommand.run((
      parentPath: pickedPath,
      vaultName: vaultName.trim(),
    ));
  }

  Future<String?> _showVaultNameDialog(
    BuildContext context,
    String parentPath,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create Vault'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Vault name',
              hintText: 'My Vault',
            ),
            onSubmitted: (value) {
              Navigator.of(dialogContext).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndOpen() async {
    final path = await di<IFileSystemService>().pickDirectory();
    if (path == null) return;
    di<VaultSystem>().openVaultCommand.run(path);
  }
}
