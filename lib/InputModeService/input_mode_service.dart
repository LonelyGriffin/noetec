// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// The current input mode determined by the most recent pointer event.
///
/// Used to switch UI behaviour (e.g. selection handles, toolbar visibility)
/// on the fly, similarly to how games switch between gamepad and keyboard
/// layouts based on the last input device used.
enum InputMode { touch, mouse }

/// Tracks the current [InputMode] based on incoming pointer events.
///
/// Registered as a singleton in DI.  Widgets watch [mode] to reactively
/// adjust their behaviour (e.g. show mobile selection handles, display the
/// action toolbar above the keyboard, etc.).
///
/// This is the foundation for a broader input-mode system.  In the future
/// it can be extended with keyboard mode (hardware vs virtual), stylus
/// pressure support, and other input aspects.
class InputModeService {
  final ValueNotifier<InputMode> mode = ValueNotifier(InputMode.mouse);

  /// Call on every [PointerDownEvent] to keep [mode] up-to-date.
  void updateFromPointerEvent(PointerEvent event) {
    final newMode = switch (event.kind) {
      PointerDeviceKind.touch || PointerDeviceKind.stylus => InputMode.touch,
      _ => InputMode.mouse,
    };
    if (mode.value != newMode) {
      mode.value = newMode;
    }
  }
}
