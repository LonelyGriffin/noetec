---
name: integration-testing
description: "Run Noetec integration tests with the project runner, use slow-motion mode, and troubleshoot GPU/EGL launch failures on WSLg."
---

# Integration tests

Use the project runner from the repository root:

```sh
dart run scripts/run_integration_tests.dart
dart run scripts/run_integration_tests.dart integration_test/<file>.dart
```

The runner uses one process per test file and defaults to `--jobs 1`. See
[CONTRIBUTING](../../docs/CONTRIBUTING.md) for the contribution checks. These
instructions do not require a particular agent platform or machine.

## WSLg troubleshooting

On headless WSL2 + WSLg, the GPU/EGL path can cause the second app start in one
`flutter test` session to fail with `The log reader stopped unexpectedly, or
never started` or `Failed to load ...: Unable to start the app`.

- Use `--jobs 1` on affected WSLg environments; parallel runs are experimental
  and may flake under GPU/EGL contention even with software rendering.
- Re-run a failing file alone to distinguish batch/environment failures from
  reproducible test failures. Do not assume every failure is an environment issue.

### Software rendering

Force Mesa software rendering for the app process:

```sh
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe flutter test integration_test/<file>.dart
```

The runner injects these variables on non-Windows systems; Windows uses its
native rendering path. The shell example above is for Linux/WSL. Notes:

- Use the runner's `--jobs N` for multiple test processes, not
  `flutter test --concurrency`; prefer sequential runs on affected WSLg systems.
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
