// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/DocumentSystem/opened_documents_manager.dart';
import 'package:noetec/IdService/id_service.dart';
import 'package:noetec/UserActionSystem/user_action_service.dart';
import 'package:noetec/UserInputSystem/user_input_service.dart';

/// All services wired together for testing, without DI container.
class TestEnvironment {
  final OpenedDocumentsManager documentsManager;
  final IdService idService;
  final UserActionService actionService;
  final UserInputService inputService;

  TestEnvironment({
    required this.documentsManager,
    required this.idService,
    required this.actionService,
    required this.inputService,
  });
}

/// Creates a fully wired [TestEnvironment] with all services connected.
TestEnvironment createTestEnvironment() {
  var idCounter = 0;
  final idService = IdService(() => 'generated-id-${idCounter++}');
  final documentsManager = OpenedDocumentsManager();
  final actionService = UserActionService(documentsManager, idService);
  final inputService = UserInputService(
    documentsManager: documentsManager,
    actionService: actionService,
  );
  return TestEnvironment(
    documentsManager: documentsManager,
    idService: idService,
    actionService: actionService,
    inputService: inputService,
  );
}
