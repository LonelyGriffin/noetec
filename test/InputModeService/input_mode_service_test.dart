// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/InputModeService/input_mode_service.dart';

/// Helper: creates a minimal [PointerDownEvent] with the given [kind].
///
/// Note: [PointerDeviceKind.trackpad] is not valid for [PointerDownEvent]
/// (Flutter asserts against it), so use [_pointerHover] for trackpad tests.
PointerDownEvent _pointerDown(PointerDeviceKind kind) {
  return PointerDownEvent(kind: kind, position: Offset.zero);
}

/// Helper: creates a [PointerHoverEvent] — usable with any device kind
/// including trackpad.
PointerHoverEvent _pointerHover(PointerDeviceKind kind) {
  return PointerHoverEvent(kind: kind, position: Offset.zero);
}

void main() {
  late InputModeService service;

  setUp(() {
    service = InputModeService();
  });

  group('InputModeService', () {
    test('default mode is mouse', () {
      expect(service.mode.value, InputMode.mouse);
    });

    test('touch pointer switches mode to touch', () {
      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));
      expect(service.mode.value, InputMode.touch);
    });

    test('mouse pointer switches mode to mouse', () {
      // Start in touch mode first.
      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));
      expect(service.mode.value, InputMode.touch);

      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.mouse));
      expect(service.mode.value, InputMode.mouse);
    });

    test('stylus pointer switches mode to touch', () {
      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.stylus));
      expect(service.mode.value, InputMode.touch);
    });

    test('repeated touch events do not notify when already in touch mode', () {
      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));

      int notifyCount = 0;
      service.mode.addListener(() => notifyCount++);

      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));
      expect(
        notifyCount,
        0,
        reason: 'same mode should not trigger notification',
      );
    });

    test('mode toggles correctly through touch -> mouse -> touch', () {
      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));
      expect(service.mode.value, InputMode.touch);

      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.mouse));
      expect(service.mode.value, InputMode.mouse);

      service.updateFromPointerEvent(_pointerDown(PointerDeviceKind.touch));
      expect(service.mode.value, InputMode.touch);
    });

    test('trackpad pointer is treated as mouse', () {
      service.updateFromPointerEvent(_pointerHover(PointerDeviceKind.trackpad));
      expect(service.mode.value, InputMode.mouse);
    });
  });
}
