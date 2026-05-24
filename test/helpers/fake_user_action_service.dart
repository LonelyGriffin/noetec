// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/UserActionSystem/user_action.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';

/// A test double for [UserActionService] that records dispatched actions
/// instead of applying them to the document model.
class FakeUserActionService extends UserActionService {
  FakeUserActionService()
      : super(OpenedDocumentsManager()); // dummy manager, never used

  final List<UserAction> actions = [];

  @override
  void handleAction(UserAction action) {
    actions.add(action);
  }

  /// Returns the last dispatched action, or throws if none.
  UserAction get lastAction {
    if (actions.isEmpty) throw StateError('No actions dispatched');
    return actions.last;
  }

  /// Clears the recorded actions list.
  void reset() => actions.clear();
}
