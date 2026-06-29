// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../entity/page/page_edit_action.dart';
import '../../systems/page_system/page_system.dart';
import '../../systems/vault/closing_event.dart';
import '../../systems/vault/vault_system.dart';
import 'wal_service.dart';

enum PageSaveState { clean, dirty, saving, error }

final class PageSaveInfo {
  final PageSaveState state;
  final DateTime? lastSaved;
  final String? lastError;

  const PageSaveInfo({
    this.state = PageSaveState.clean,
    this.lastSaved,
    this.lastError,
  });

  PageSaveInfo copyWith({
    PageSaveState? state,
    DateTime? lastSaved,
    String? lastError,
  }) => PageSaveInfo(
    state: state ?? this.state,
    lastSaved: lastSaved ?? this.lastSaved,
    lastError: lastError ?? this.lastError,
  );
}

class PersistenceSystem {
  PersistenceSystem({
    required WalService wal,
    required PageSystem pageSystem,
    required VaultSystem vaultSystem,
  }) : _wal = wal,
       _pageSystem = pageSystem,
       _vaultSystem = vaultSystem {
    _closingSubscription = _vaultSystem.closing.listen(_onClosing);
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final WalService _wal;
  final PageSystem _pageSystem;
  final VaultSystem _vaultSystem;
  final Map<String, ValueNotifier<PageSaveInfo>> _saveStates = {};
  StreamSubscription<ClosingEvent>? _closingSubscription;
  bool _active = false;

  ValueNotifier<PageSaveInfo> saveStateOf(String pageId) => _saveStates
      .putIfAbsent(pageId, () => ValueNotifier(const PageSaveInfo()));

  void registerPage(String pageId, String relativePath) {
    _wal.register(pageId, relativePath);
    _saveStates.putIfAbsent(pageId, () => ValueNotifier(const PageSaveInfo()));
  }

  void unregisterPage(String pageId) {
    _wal.unregister(pageId);
    _saveStates[pageId]?.dispose();
    _saveStates.remove(pageId);
  }

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      _active = true;
      _pageSystem.actionDispatcher.addListener(_onAction);
    } else {
      _active = false;
      _pageSystem.actionDispatcher.removeListener(_onAction);
    }
  }

  void _onClosing(ClosingEvent event) {
    event.waitFor(saveAll());
  }

  void _onAction(PageEditAction action) {
    if (!_active) return;
    final pageId = _pageSystem.activePageId.value;
    if (pageId == null) return;
    _wal.appendAction(pageId, action);
    markDirty(pageId);
  }

  void markDirty(String pageId) {
    final notifier = _saveStates[pageId];
    if (notifier == null) return;
    notifier.value = notifier.value.copyWith(state: PageSaveState.dirty);
  }

  Future<void> savePage(String pageId) async {
    final notifier = _saveStates[pageId];
    if (notifier == null) return;
    if (notifier.value.state == PageSaveState.clean) return;

    notifier.value = notifier.value.copyWith(state: PageSaveState.saving);
    try {
      await _wal.flush(pageId);
      await _pageSystem.savePage(pageId);
      await _wal.clear(pageId);
      notifier.value = PageSaveInfo(
        state: PageSaveState.clean,
        lastSaved: DateTime.now(),
      );
    } catch (error) {
      notifier.value = notifier.value.copyWith(
        state: PageSaveState.error,
        lastError: error.toString(),
      );
    }
  }

  Future<void> saveAll() async {
    for (final pageId in _saveStates.keys.toList()) {
      if (_saveStates[pageId]!.value.state == PageSaveState.dirty) {
        await savePage(pageId);
      }
    }
  }

  void dispose() {
    _closingSubscription?.cancel();
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    _pageSystem.actionDispatcher.removeListener(_onAction);
    for (final notifier in _saveStates.values) {
      notifier.dispose();
    }
    _saveStates.clear();
  }
}
