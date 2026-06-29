// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import '../../entity/page/page_edit_action.dart';

typedef ActionListener = void Function(PageEditAction action);

class PageActionDispatcher {
  final List<ActionListener> _listeners = [];

  void addListener(ActionListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ActionListener listener) {
    _listeners.remove(listener);
  }

  void dispatch(PageEditAction action) {
    for (final listener in List.of(_listeners)) {
      listener(action);
    }
  }
}
