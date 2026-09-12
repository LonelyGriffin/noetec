// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:command_it/command_it.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/user_device_controller.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:watch_it/watch_it.dart';

/// The settings panel: vault switching plus the user & device management UI
/// (NOET-33).
///
/// The panel is a pure view over [UserDeviceController]: it watches the
/// [UserDeviceController.state] notifier and routes user actions through the
/// controller's commands. The identity seed is shown only on explicit user
/// action and never stored in widget state or the controller.
class SettingsPanel extends WatchingWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = di<UserDeviceController>();
    final snapshot = watchValue<UserDeviceController, UserDeviceSnapshot?>((c) => c.state);

    _registerErrorHandlers(context, controller);

    // Populate the snapshot the first time the panel is built (and again
    // after a vault change, which resets [snapshot] to null).
    if (snapshot == null) {
      controller.refreshCommand.run();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: () => di<VaultSystem>().closeVaultCommand.run(), icon: const Icon(Icons.folder_open), label: const Text('Open Another Vault')),
          const SizedBox(height: 24),
          if (snapshot == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            _DeviceSection(controller: controller, snapshot: snapshot),
            const SizedBox(height: 20),
            _UsersSection(controller: controller, snapshot: snapshot),
            const SizedBox(height: 8),
            Expanded(
              child: _DevicesSection(controller: controller, snapshot: snapshot),
            ),
          ],
        ],
      ),
    );
  }

  /// Wires every command's `.errors` to a snackbar with a short,
  /// user-presentable message ([UserDeviceError.message]).
  void _registerErrorHandlers(BuildContext context, UserDeviceController controller) {
    _onCommandError<UserDeviceController, ({String name, String publicKeyBase64Url})?>(context, (c) => c.addUserCommand.errors);
    _onCommandError<UserDeviceController, String?>(context, (c) => c.revokeUserCommand.errors);
    _onCommandError<UserDeviceController, String?>(context, (c) => c.revokeDeviceCommand.errors);
    _onCommandError<UserDeviceController, String?>(context, (c) => c.renameDeviceCommand.errors);
  }

  void _onCommandError<T extends Object, P>(BuildContext context, ValueListenable<CommandError<P>?> Function(T) select) {
    registerHandler<T, CommandError<P>?>(
      select: select,
      handler: (context, error, cancel) {
        if (error == null) return;
        final message = error.error is UserDeviceError ? (error.error as UserDeviceError).message : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }
}

/// The "this device" area: name, public key, and the rename + show-seed
/// actions.
class _DeviceSection extends WatchingWidget {
  const _DeviceSection({required this.controller, required this.snapshot});

  final UserDeviceController controller;
  final UserDeviceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final device = snapshot.device;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.desktop_windows_outlined, title: 'This device'),
        if (device == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('No device yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.name,
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.edit, size: 18), tooltip: 'Rename device', onPressed: () => _renameDevice(context)),
                    ],
                  ),
                  _KeyRow(publicKey: device.publicKey, label: 'Public key'),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(onPressed: () => _showSeed(context), icon: const Icon(Icons.key, size: 18), label: const Text('Show recovery seed')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _renameDevice(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _DeviceRenameDialog(controller: controller, currentName: snapshot.device!.name),
    );
  }

  void _showSeed(BuildContext context) async {
    final seed = await controller.showSeed();
    if (seed == null || !context.mounted) return;
    await _showSeedDialog(context, seed);
  }

  Future<void> _showSeedDialog(BuildContext context, String seed) async {
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recovery seed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Write these 24 words down and store them safely. They are the only backup of your identity — anyone with this seed can restore your identity.'),
            const SizedBox(height: 12),
            SelectableText(seed, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              // Copying the seed to the clipboard is an explicit user action;
              // the dialog stays open so the user can close it deliberately.
              await Clipboard.setData(ClipboardData(text: seed));
              messenger.showSnackBar(const SnackBar(content: Text('Seed copied to clipboard')));
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

/// The "Users" area: the user list from `users.json`, with add/revoke.
class _UsersSection extends StatefulWidget {
  const _UsersSection({required this.controller, required this.snapshot});

  final UserDeviceController controller;
  final UserDeviceSnapshot snapshot;

  @override
  State<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<_UsersSection> {
  final Set<String> _revealed = {};

  void _toggleRevealed(String userId) {
    setState(() {
      if (!_revealed.add(userId)) {
        _revealed.remove(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = widget.snapshot.users;
    final isOwner = widget.controller.isOperatorOwner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(icon: Icons.people_outline, title: 'Users'),
            ),
            if (isOwner) IconButton(icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), tooltip: 'Add user', onPressed: () => _addUser(context)),
          ],
        ),
        if (users == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('No user registry yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          for (final user in users.users)
            _UserTile(
              user: user,
              isOwner: user.userId == users.ownerUserId,
              canRevoke: isOwner,
              isRevealed: _revealed.contains(user.userId),
              onToggleRevealed: () => _toggleRevealed(user.userId),
              onRevoke: () => _revokeUser(context, user),
            ),
      ],
    );
  }

  void _addUser(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddUserDialog(controller: widget.controller),
    );
  }

  void _revokeUser(BuildContext context, UserRecord user) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke user'),
        content: Text('Revoke ${user.name} (${user.userId})? Their devices will lose access to the vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.controller.revokeUserCommand.run(user.userId);
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }
}

/// The "Devices" area: the operator's device list from the device registry.
class _DevicesSection extends StatefulWidget {
  const _DevicesSection({required this.controller, required this.snapshot});

  final UserDeviceController controller;
  final UserDeviceSnapshot snapshot;

  @override
  State<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<_DevicesSection> {
  final Set<String> _revealed = {};

  void _toggleRevealed(String deviceUuid) {
    setState(() {
      if (!_revealed.add(deviceUuid)) {
        _revealed.remove(deviceUuid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operator = widget.snapshot.operator;
    final registry = widget.snapshot.devices;
    final localDeviceUuid = widget.snapshot.device?.uuid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.devices_other, title: 'Devices'),
        if (operator == null || registry == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('No device registry yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else ...[
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final device in registry.devices)
                  _DeviceTile(
                    device: device,
                    isLocal: device.deviceUuid == localDeviceUuid,
                    isRevealed: _revealed.contains(device.deviceUuid),
                    onToggleRevealed: () => _toggleRevealed(device.deviceUuid),
                    onRevoke: () => _revokeDevice(context, device),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _revokeDevice(BuildContext context, DeviceRecord device) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke device'),
        content: Text('Revoke "${device.deviceName}" (${device.deviceUuid})? This device will lose access to the vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.controller.revokeDeviceCommand.run(device.deviceUuid);
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }
}

/// A section header (icon + title).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A user row in the user list.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.isOwner, required this.canRevoke, required this.isRevealed, required this.onToggleRevealed, required this.onRevoke});

  final UserRecord user;
  final bool isOwner;
  final bool canRevoke;
  final bool isRevealed;
  final VoidCallback onToggleRevealed;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Icon(isOwner ? Icons.shield_outlined : Icons.person_outline, color: theme.colorScheme.primary),
            title: Text(user.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              user.userId,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOwner) const _RoleBadge(label: 'owner'),
                if (canRevoke) IconButton(icon: const Icon(Icons.person_remove_alt_1_outlined, size: 18), tooltip: 'Revoke user', onPressed: onRevoke),
              ],
            ),
          ),
          if (!user.isRemoved)
            _KeyRow(publicKey: user.publicKey, label: 'Public key', revealed: isRevealed, onToggleReveal: onToggleRevealed)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Revoked', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// A device row in the operator's device list.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.isLocal, required this.isRevealed, required this.onToggleRevealed, required this.onRevoke});

  final DeviceRecord device;
  final bool isLocal;
  final bool isRevealed;
  final VoidCallback onToggleRevealed;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Icon(isLocal ? Icons.desktop_windows_outlined : Icons.tablet_mac_outlined, color: theme.colorScheme.primary),
            title: Text(device.deviceName, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              device.deviceUuid,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLocal) const _RoleBadge(label: 'this device'),
                if (!device.isRemoved) IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: 'Revoke device', onPressed: onRevoke),
              ],
            ),
          ),
          if (!device.isRemoved)
            _KeyRow(publicKey: device.devicePublicKey, label: 'Public key', revealed: isRevealed, onToggleReveal: onToggleRevealed)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Revoked', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// A short pill badge (e.g. "owner", "this device").
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// A truncated key display with an optional reveal toggle.
///
/// Keys are public material, but the truncated default keeps the panel
/// readable; revealing is an explicit user action.
class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.publicKey, required this.label, this.revealed = false, this.onToggleReveal});

  final String? publicKey;
  final String label;
  final bool revealed;
  final VoidCallback? onToggleReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = publicKey;
    if (value == null || value.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('$label: —', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value.length > 24 && !revealed ? '…${_middle(value)}…' : value,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onToggleReveal != null)
            IconButton(
              icon: Icon(revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
              tooltip: revealed ? 'Hide key' : 'Show key',
              onPressed: onToggleReveal,
            ),
        ],
      ),
    );
  }

  static String _middle(String value) {
    const keep = 8;
    if (value.length <= keep * 2 + 1) return value;
    return '${value.substring(0, keep)}…${value.substring(value.length - keep)}';
  }
}

/// The "add a user" dialog: a display name plus the user's base64url
/// Ed25519 identity public key (the new user's seed never leaves their own
/// device — NOET-32 flow 3).
class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog({required this.controller});

  final UserDeviceController controller;

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _nameController = TextEditingController();
  final _keyController = TextEditingController();
  bool _invalidKey = false;

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  bool _isValidKey(String value) {
    try {
      final bytes = base64UrlDecode(value);
      return bytes.length == 32;
    } on Exception {
      return false;
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final key = _keyController.text.trim();
    if (name.isEmpty || !_isValidKey(key)) {
      setState(() => _invalidKey = true);
      return;
    }
    Navigator.of(context).pop();
    widget.controller.addUserCommand.run((name: name, publicKeyBase64Url: key));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name', hintText: "Alice's key"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: 'Public key (base64url)',
              hintText: 'Ed25519 identity key',
              errorText: _invalidKey ? 'A base64url 32-byte Ed25519 key is required' : null,
            ),
            style: const TextStyle(fontFamily: 'monospace'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask the user for their public key. Their recovery seed never leaves their own device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add user')),
      ],
    );
  }
}

/// The "rename device" dialog.
class _DeviceRenameDialog extends StatefulWidget {
  const _DeviceRenameDialog({required this.controller, required this.currentName});

  final UserDeviceController controller;
  final String currentName;

  @override
  State<_DeviceRenameDialog> createState() => _DeviceRenameDialogState();
}

class _DeviceRenameDialogState extends State<_DeviceRenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop();
    widget.controller.renameDeviceCommand.run(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename device'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Device name', hintText: 'My Laptop'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _controller.text.trim().isEmpty ? null : _submit, child: const Text('Rename')),
      ],
    );
  }
}
