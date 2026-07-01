// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/page.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/page_system/page_action_dispatcher.dart';
import 'package:noetec/systems/page_system/page_clipboard_subsystem.dart';
import 'package:noetec/systems/page_system/page_editing_subsystem.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';
import 'package:noetec/systems/page_system/page_selection_subsystem.dart';
import 'package:noetec/systems/vault/closing_event.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:path/path.dart' as p;

final class SessionState {
  final List<String> openPagePaths;
  final String? activePagePath;

  const SessionState({required this.openPagePaths, this.activePagePath});

  Map<String, dynamic> toJson() => {
    'open_pages': openPagePaths,
    'active_page': activePagePath,
  };

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
    openPagePaths: (json['open_pages'] as List).cast<String>(),
    activePagePath: json['active_page'] as String?,
  );
}

class PageSystem {
  final Map<String, PageEntity> openPages = {};
  final ValueNotifier<String?> activePageId = ValueNotifier(null);
  final ValueNotifier<int> openPagesVersion = ValueNotifier(0);

  final IIdService _idService;
  final MarkdownSystem _markdownSystem;
  final IFileSystemService _fileSystem;
  final VaultSystem _vaultSystem;
  final PageActionDispatcher actionDispatcher = PageActionDispatcher();

  String? _vaultRootPath;
  final Map<String, String> _pathToPageId = {};

  final _pageOpenedController =
      StreamController<(String pageId, String relativePath)>.broadcast(
        sync: true,
      );
  Stream<(String pageId, String relativePath)> get pageOpened =>
      _pageOpenedController.stream;

  final _pageClosedController = StreamController<String>.broadcast(sync: true);
  Stream<String> get pageClosed => _pageClosedController.stream;

  final _pageCreatedController =
      StreamController<(String pageId, String relativePath)>.broadcast(
        sync: true,
      );
  Stream<(String pageId, String relativePath)> get pageCreated =>
      _pageCreatedController.stream;

  late final PageEditingSubsystem editing;
  late final PageSelectionSubsystem selection;
  late final PageClipboardSubsystem clipboard;

  StreamSubscription<ClosingEvent>? _closingSubscription;
  StreamSubscription<VaultEntity>? _vaultCreatedSubscription;

  PageSystem(
    this._idService,
    this._markdownSystem,
    this._fileSystem,
    this._vaultSystem,
  ) {
    editing = PageEditingSubsystem(this, _idService, actionDispatcher);
    selection = PageSelectionSubsystem(this);
    clipboard = PageClipboardSubsystem(this, _markdownSystem, _idService);
    _closingSubscription = _vaultSystem.closing.listen(_onClosing);
    _vaultSystem.currentVault.addListener(_onVaultChanged);
    _vaultCreatedSubscription = _vaultSystem.vaultCreated.listen(
      _onVaultCreated,
    );
  }

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      _vaultRootPath = vault.rootPath;
      unawaited(restoreSession());
    } else {
      clearAllPages();
      _vaultRootPath = null;
    }
  }

  Future<void> _onVaultCreated(VaultEntity vault) async {
    _vaultRootPath = vault.rootPath;
    await initializeForNewVault();
  }

  Future<void> initializeForNewVault() async {
    try {
      final page = await loadPage('pages/welcome.md');
      _pageCreatedController.add((page.id, 'pages/welcome.md'));
      await saveSession();
    } catch (_) {}
  }

  void _onClosing(ClosingEvent event) {
    event.waitFor(saveSession());
  }

  PageEntity? getActivePage() {
    final id = activePageId.value;
    if (id == null) return null;
    return openPages[id];
  }

  void setActivePage(String pageId) {
    activePageId.value = pageId;
    unawaited(saveSession());
  }

  Future<PageEntity> loadPage(String relativePath) async {
    final existingId = _pathToPageId[relativePath];
    if (existingId != null && openPages.containsKey(existingId)) {
      final page = openPages[existingId]!;
      activePageId.value = page.id;
      await saveSession();
      return page;
    }

    final absolutePath = p.normalize(p.join(_vaultRootPath!, relativePath));
    final raw = await _fileSystem.readFile(absolutePath);
    final (:frontmatter, :content) = PageFrontmatterCodec.parse(raw);

    final page = PageEntity(id: frontmatter.id, relativePath: relativePath);
    final parsedBlocks = _markdownSystem.parseMarkdown(content);

    for (final block in parsedBlocks) {
      page.rootBlocks.add(block);
      page.blocks[block.id] = block;
    }

    openPages[page.id] = page;
    _pathToPageId[relativePath] = page.id;
    activePageId.value = page.id;
    _pageOpenedController.add((page.id, relativePath));
    openPagesVersion.value++;

    await saveSession();

    return page;
  }

  Future<String> savePage(String pageId) async {
    final page = openPages[pageId];
    if (page == null || _vaultRootPath == null) {
      return '';
    }

    final textBlocks = page.rootBlocks.whereType<TextBlockEntity>().toList();
    final markdown = _markdownSystem.serializeBlocks(textBlocks);

    final hash = PageFrontmatterCodec.computeContentHash(markdown);
    final frontmatter = PageFrontmatter(
      id: page.id,
      contentHash: 'sha256:$hash',
      modified: DateTime.now().toUtc(),
    );

    final fileContent = PageFrontmatterCodec.encode(frontmatter, markdown);
    final absolutePath = p.normalize(
      p.join(_vaultRootPath!, page.relativePath),
    );
    await _fileSystem.writeFile(absolutePath, fileContent);
    return 'sha256:$hash';
  }

  void closePage(String pageId) {
    final page = openPages.remove(pageId);
    if (page != null) {
      _pathToPageId.remove(page.relativePath);
      page.dispose();
      _pageClosedController.add(pageId);
      openPagesVersion.value++;
    }

    if (activePageId.value == pageId) {
      activePageId.value = openPages.keys.isEmpty ? null : openPages.keys.first;
    }
    unawaited(saveSession());
  }

  void clearAllPages() {
    for (final page in openPages.values) {
      page.dispose();
    }
    openPages.clear();
    _pathToPageId.clear();
    activePageId.value = null;
    openPagesVersion.value++;
  }

  static const _sessionFile = '.noetec/session.json';

  Future<void> saveSession() async {
    if (_vaultRootPath == null) return;
    final openPaths = openPages.values
        .map((page) => page.relativePath)
        .toList();
    final activePage = getActivePage();
    final state = SessionState(
      openPagePaths: openPaths,
      activePagePath: activePage?.relativePath,
    );
    await _fileSystem.writeFile(
      p.normalize(p.join(_vaultRootPath!, _sessionFile)),
      jsonEncode(state.toJson()),
    );
  }

  Future<void> restoreSession() async {
    if (_vaultRootPath == null) return;
    final filePath = p.normalize(p.join(_vaultRootPath!, _sessionFile));
    if (!await _fileSystem.fileExists(filePath)) return;
    try {
      final raw = await _fileSystem.readFile(filePath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final state = SessionState.fromJson(json);
      for (final relativePath in state.openPagePaths) {
        try {
          await loadPage(relativePath);
        } catch (_) {}
      }
      if (state.activePagePath != null) {
        try {
          await loadPage(state.activePagePath!);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void dispose() {
    _closingSubscription?.cancel();
    _vaultCreatedSubscription?.cancel();
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    _pageOpenedController.close();
    _pageClosedController.close();
    _pageCreatedController.close();
    for (final page in openPages.values) {
      page.dispose();
    }
    openPages.clear();
    activePageId.dispose();
  }
}
