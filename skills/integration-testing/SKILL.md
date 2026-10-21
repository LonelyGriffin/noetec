---
name: integration-testing
description: "Run the noetec integration test suite on the headless WSL2 daemon box — force Mesa software rendering, use the sequential runner, and understand the GPU/EGL launch quirks. Use when running integration_test/, scripts/run_integration_tests.dart, or hitting 'The log reader stopped unexpectedly' / 'Unable to start the app' failures."
---

# Integration tests (headless WSL)

Integration tests on the daemon box (WSL2 + WSLg, `DISPLAY=:0`) are sensitive to the GPU/EGL path. The app launches with WSLg's Vulkan/GPU stack, and the **second** app start within a single `flutter test` session fails with `The log reader stopped unexpectedly, or never started` / `Failed to load ...: Unable to start the app` — the first file in the session usually passes.

## Rules (non-negotiable)

- **Run the full suite with `--jobs 1`** (sequential). This is the only supported mode on the WSL box.
- **`--jobs > 1` is experimental and unsupported** — parallel runs flake under GPU/EGL contention even with software rendering. Do not rely on it.
- **Before declaring a failure a regression**, re-run the failing file **alone** in clean single-file isolation (`dart run scripts/run_integration_tests.dart integration_test/<file>.dart`). Batch failures are usually WSLg contention, not code bugs.

## Fix

Force Mesa software rendering for the app process:

```sh
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe flutter test integration_test/<file>.dart
```

`scripts/run_integration_tests.dart` injects both variables into every `flutter test` child, so it works without the prefix. Notes:

- `flutter test --concurrency` is **ignored for integration tests** (they run serially per file by design); parallelism is only possible via `--jobs N` in the runner (multiple processes) — but per the Rules above, parallel is experimental and flaky.
- WSLg's EGL init also prints GPU warnings on first app start; harmless under software rendering.
- This is an environment workaround for a WSLg/Flutter desktop launch bug, not an app issue.

## Slow-motion mode (human-watchable runs)

Off by default — a plain run behaves exactly as before. Add flags to any runner
command to watch a test in real time:

```sh
dart run scripts/run_integration_tests.dart integration_test/<file>.dart --slow
dart run scripts/run_integration_tests.dart integration_test/<file>.dart --speed 8 --hud-corner tl
```

- `--slow` — enable the mode; `--speed N` — `timeDilation` multiplier (default 4,
  implies `--slow`); `--hud-corner tl|tr|bl|br` — HUD panel corner (default `br`,
  implies `--slow`).
- The HUD captures and displays key presses and pointer events (hover/move/down/
  up/pan) live, in a translucent corner panel. It observes only — `IgnorePointer`
  + translucent `Listener` — so the app under test receives every event unchanged.
- Implementation: `pumpTestApp(tester)` (replaces the old
  `pumpWidget(const MainApp())` in every test file) honors the `--dart-define`
  contract `NOETEC_SLOW` / `NOETEC_SPEED` / `NOETEC_HUD_CORNER`.
- `SlowMotionHud` owns the `timeDilation` lifecycle (`initState` sets it,
  `dispose` restores `1.0`), which satisfies the test binding's
  `debugAssertNoTimeDilation` invariant — do not set `timeDilation` ad hoc in
  tests, that invariant failure is guaranteed.
