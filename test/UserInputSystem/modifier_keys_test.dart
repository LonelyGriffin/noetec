// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_environment.dart';

void main() {
  late TestEnvironment env;

  setUp(() {
    env = createTestEnvironment();
  });

  // ---------------------------------------------------------------------------
  // Modifier keys
  // ---------------------------------------------------------------------------
  group('modifier keys', () {
    test('tracks ctrl key state', () {
      expect(env.inputService.ctrlPressed, isFalse);

      env.inputService.handleKeyEvent(
        'doc',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.ctrlPressed, isTrue);

      env.inputService.handleKeyUp(
        KeyUpEvent(
          logicalKey: LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.ctrlPressed, isFalse);
    });

    test('tracks shift key state', () {
      env.inputService.handleKeyEvent(
        'doc',
        KeyDownEvent(
          logicalKey: LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(env.inputService.shiftPressed, isTrue);
    });
  });
}
