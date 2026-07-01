// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/user_input_system/handlers/ime_input_handler.dart';

class ClipboardInputHandler {
  late final PageSystem _pageSystem;
  late final ImeInputHandler _ime;

  void init(PageSystem pageSystem, ImeInputHandler ime) {
    _pageSystem = pageSystem;
    _ime = ime;
  }

  void handleSelectAll() {
    final page = _pageSystem.getActivePage();
    if (page == null) return;

    _pageSystem.selection.selectAll();

    final pageId = _pageSystem.activePageId.value;
    if (pageId != null) {
      _ime.syncImeState(pageId);
    }
  }

  void handleCopy() {
    final markdown = _pageSystem.clipboard.copy();
    if (markdown == null) return;

    Clipboard.setData(ClipboardData(text: markdown));
  }

  void handleCut() {
    final markdown = _pageSystem.clipboard.getCutMarkdown();
    if (markdown == null) return;

    Clipboard.setData(ClipboardData(text: markdown));

    _pageSystem.editing.deleteSelection();

    final pageId = _pageSystem.activePageId.value;
    if (pageId != null) {
      _ime.syncImeState(pageId);
    }
  }

  void handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.isEmpty) return;

    _pageSystem.clipboard.paste(data.text!);

    final pageId = _pageSystem.activePageId.value;
    if (pageId != null) {
      _ime.syncImeState(pageId);
    }
  }
}
