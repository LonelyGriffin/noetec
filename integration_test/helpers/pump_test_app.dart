// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/app/main_app_widget.dart';

import 'slow_motion_hud.dart';

/// Whether the slow-motion HUD mode is enabled for this test process.
///
/// Injected via `--dart-define=NOETEC_SLOW` by `scripts/run_integration_tests.dart`
/// (`--slow` / `--speed` / `--hud-corner`). Off by default — with the flag
/// absent, [pumpTestApp] pumps the bare [MainApp] exactly as before.
const bool kSlowMotionEnabled = bool.fromEnvironment('NOETEC_SLOW', defaultValue: false);

/// The slowdown multiplier ([timeDilation]) for slow-motion runs.
const int kSlowMotionSpeed = int.fromEnvironment('NOETEC_SPEED', defaultValue: 4);

/// The HUD corner for slow-motion runs (parsed from `tl|tr|bl|br`).
const String kHudCornerRaw = String.fromEnvironment('NOETEC_HUD_CORNER', defaultValue: 'br');

/// The HUD corner as an enum, parsed from [kHudCornerRaw] (defaults to
/// [HudCorner.bottomRight] for unrecognized values).
HudCorner get kHudCorner {
  switch (kHudCornerRaw) {
    case 'tl':
      return HudCorner.topLeft;
    case 'tr':
      return HudCorner.topRight;
    case 'bl':
      return HudCorner.bottomLeft;
    case 'br':
      return HudCorner.bottomRight;
    default:
      return HudCorner.bottomRight;
  }
}

/// Pumps the app under test, honoring the slow-motion HUD config.
///
/// - **HUD off (default):** pumps `const MainApp()` — byte-for-byte the same
///   behavior as the previous `await tester.pumpWidget(const MainApp());`.
/// - **HUD on:** pumps the app wrapped in [SlowMotionHud], pinned to
///   [kHudCorner]. The HUD owns the [timeDilation] lifecycle itself: it is set
///   to [kSlowMotionSpeed] in `initState` and restored to `1.0` in `dispose`,
///   so the test binding's end-of-test invariant (`debugAssertNoTimeDilation`)
///   always holds — no `addTearDown` bookkeeping needed here.
Future<void> pumpTestApp(WidgetTester tester) async {
  if (!kSlowMotionEnabled) {
    await tester.pumpWidget(const MainApp());
    return;
  }
  final speed = kSlowMotionSpeed.toDouble();
  await tester.pumpWidget(SlowMotionHud(corner: kHudCorner, speed: speed, child: const MainApp()));
}
