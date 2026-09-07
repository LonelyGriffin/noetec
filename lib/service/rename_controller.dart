// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';

import 'package:command_it/command_it.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:noetec/systems/vault/vault_system.dart';

/// Lifecycle of a single "rename a page" session.
enum _RenamePhase {
  /// No rename session is active.
  idle,

  /// A node is in rename mode and the user is editing its name.
  editing,

  /// [RenameController.confirmCommand] is running
  /// [VaultFileService.renamePage]; any further begin/confirm/cancel intents
  /// are ignored until the rename settles.
  committing,
}

/// Owns the "rename a page" session so the widget tree can stay a pure view.
///
/// This is the fix for NOET-17 (double-commit on page rename). Previously the
/// commit-once guarantee lived in the widget as an ad-hoc flag; the root cause
/// was that two different events ("the user finished the session" and "focus
/// left the field") both reached `_commitRename`, and the widget's own
/// teardown (removing the field) re-entered through the focus-loss path.
///
/// Here the guarantee is an invariant of this state machine: [confirmCommand]
/// transitions `editing -> committing` *before* it calls
/// [VaultFileService.renamePage], so a second confirm (Enter racing the
/// focus-loss handler, a repeated Enter, or the field being torn down) observes
/// `committing` and is a no-op. The widget no longer calls
/// [VaultFileService.renamePage] at all and no longer tracks "has it
/// committed?" itself.
///
/// Real rename errors ([PageNameConflictException], [PageNameInvalidException])
/// are intentionally *not* caught here: they propagate to [confirmCommand]'s
/// error surface (`.errors`), exactly like other commands in the app. The
/// state machine only deduplicates; it does not swallow errors.
final class RenameController {
  RenameController(this._vaultFileService, this._vaultSystem) {
    // Mirror the previous `VaultFileService` behavior of clearing the active
    // rename whenever the vault is opened or closed: a rename must never be
    // left armed against a stale or closed vault.
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final VaultFileService _vaultFileService;
  final VaultSystem _vaultSystem;

  /// Relative path of the node currently in rename mode, or `null`.
  ///
  /// Single source of truth for the tree (replaces the former
  /// `VaultFileService.renamingPath` notifier).
  final CustomValueNotifier<String?> activePath = CustomValueNotifier<String?>(
    null,
  );

  _RenamePhase _phase = _RenamePhase.idle;
  String? _target;

  /// Arms a rename session for [relativePath] and makes it the active node.
  ///
  /// A no-op while a commit is in flight: a new session is never armed in the
  /// middle of an in-progress rename.
  late final beginCommand = Command.createAsyncNoResult<String>(
    _begin,
    debugName: 'renameBegin',
  );

  /// Commits the rename with [newName], running
  /// [VaultFileService.renamePage] at most once per session.
  ///
  /// An empty [newName], no active vault, or no armed session closes the
  /// session without renaming. A real rename error is allowed to propagate to
  /// the command's `.errors`; the session is still closed afterward.
  late final confirmCommand = Command.createAsyncNoResult<String>(
    _confirm,
    debugName: 'renameConfirm',
  );

  /// Abandons the current session without renaming.
  ///
  /// A no-op while a commit is in flight (cancelling mid-rename would leave
  /// the tree inconsistent with an in-flight file rename).
  late final cancelCommand = Command.createAsyncNoParamNoResult(
    _cancel,
    debugName: 'renameCancel',
  );

  Future<void> _begin(String relativePath) async {
    if (_phase == _RenamePhase.committing) return;
    _target = relativePath;
    _phase = _RenamePhase.editing;
    activePath.value = relativePath;
  }

  Future<void> _cancel() async {
    if (_phase == _RenamePhase.committing) return;
    _close();
  }

  Future<void> _confirm(String newName) async {
    if (_phase != _RenamePhase.editing) return;
    final name = newName.trim();
    final target = _target;
    if (name.isEmpty || target == null) {
      _close();
      return;
    }
    final vault = _vaultSystem.currentVault.value;
    if (vault == null) {
      _close();
      return;
    }
    _phase = _RenamePhase.committing;
    try {
      await _vaultFileService.renamePage(vault.rootPath, target, name);
    } finally {
      _close();
    }
  }

  void _onVaultChanged() {
    if (_phase == _RenamePhase.committing) return;
    _close();
  }

  void _close() {
    _phase = _RenamePhase.idle;
    _target = null;
    activePath.value = null;
  }

  /// Releases [activePath] and detaches from [VaultSystem.currentVault].
  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    beginCommand.dispose();
    confirmCommand.dispose();
    cancelCommand.dispose();
    activePath.dispose();
  }
}
