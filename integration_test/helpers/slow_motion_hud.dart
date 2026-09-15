// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Corner of the screen the HUD panel is pinned to.
enum HudCorner { topLeft, topRight, bottomLeft, bottomRight }

/// The most recent events captured for the HUD.
///
/// Backed by a [ValueNotifier] so the panel rebuilds reactively — no
/// `setState` anywhere, consistent with the project's reactive conventions.
///
/// Two independent channels (key presses, pointer events) so that a stream
/// of mouse moves cannot evict the key log a human is watching.
class HudState extends ValueNotifier<void> {
  HudState({this.maxEvents = 5}) : super(null);

  /// How many recent events each channel keeps.
  final int maxEvents;

  /// Most recent key events, oldest first.
  final List<String> keyEvents = <String>[];

  /// Most recent pointer events (down / up / hover / move / scroll / pan),
  /// oldest first.
  final List<String> pointerEvents = <String>[];

  /// Last known pointer position, or `null` before the first pointer event.
  Offset? mousePosition;

  /// Records a key [event], trimming the log to [maxEvents] entries, then
  /// notifies the panel.
  void addKeyEvent(String event) {
    _record(keyEvents, event);
    notifyListeners();
  }

  /// Records a pointer [event], trimming the log to [maxEvents] entries,
  /// then notifies the panel.
  void addPointerEvent(String event) {
    _record(pointerEvents, event);
    notifyListeners();
  }

  /// Updates the tracked pointer position and notifies the panel (so a
  /// position-only change still repaints).
  void setMousePosition(Offset position) {
    mousePosition = position;
    notifyListeners();
  }

  void _record(List<String> log, String event) {
    log.add(event);
    if (log.length > maxEvents) {
      log.removeRange(0, log.length - maxEvents);
    }
  }
}

/// Human-watchable HUD for slow-motion integration-test runs.
///
/// [child] is wrapped in a [Stack]; a full-screen translucent [Listener]
/// observes pointer events (hover / move / down / up / scroll / pan) and
/// [HardwareKeyboard.addHandler] observes key presses. The most recent events
/// are shown in a small translucent panel pinned to [corner].
///
/// The panel is wrapped in [IgnorePointer] so it never intercepts test taps,
/// and the capture [Listener] only *observes* — it never claims a hit, so the
/// app underneath keeps receiving every event exactly as before.
///
/// The HUD owns the global [timeDilation] lifecycle: set to [speed] in
/// `initState`, restored to `1.0` in `dispose`. The test binding unmounts
/// the remaining tree before its end-of-test invariant
/// (`debugAssertNoTimeDilation`), so the invariant always holds without any
/// per-test teardown bookkeeping.
class SlowMotionHud extends StatefulWidget {
  const SlowMotionHud({super.key, required this.child, this.corner = HudCorner.bottomRight, this.speed = 4, this.state});

  /// The app (or widget subtree) to watch.
  final Widget child;

  /// Corner where the panel is pinned.
  final HudCorner corner;

  /// The [timeDilation] multiplier — shown in the panel for legibility.
  final double speed;

  /// Optional shared state (handy for test assertions). When `null` a fresh
  /// [HudState] is created and disposed with the widget.
  final HudState? state;

  @override
  State<SlowMotionHud> createState() => _SlowMotionHudState();
}

class _SlowMotionHudState extends State<SlowMotionHud> {
  late final HudState _state = widget.state ?? HudState();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // Own the global timeDilation lifecycle: slow the world down for the
    // lifetime of this HUD. dispose() restores it to 1.0, which also
    // satisfies the test binding's end-of-test invariant
    // (debugAssertNoTimeDilation) — the framework unmounts the HUD before
    // verifying invariants, whether the test's own finally does it or not.
    timeDilation = widget.speed;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    timeDilation = 1.0;
    if (widget.state == null) {
      _state.dispose();
    }
    super.dispose();
  }

  /// Modifier keys are tracked by the framework (isControlPressed etc.) and
  /// only shown as a prefix on the next real key — logging them as their own
  /// entries would clutter the log ("Ctrl" followed by "Ctrl+S").
  static final Set<LogicalKeyboardKey> _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  /// Records key-down and key-repeat events. Never returns `true` so the
  /// event is NOT marked as handled — the app still receives it (text fields,
  /// shortcuts). Modifier state is read from the framework
  /// (`HardwareKeyboard.instance`), which keeps it in sync on down AND up —
  /// no local bookkeeping to drift.
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    final logical = event.logicalKey;
    if (_modifierKeys.contains(logical)) {
      return false; // modifier state is picked up on the next real key
    }
    final parts = <String>[
      if (HardwareKeyboard.instance.isControlPressed) 'Ctrl',
      if (HardwareKeyboard.instance.isShiftPressed) 'Shift',
      if (HardwareKeyboard.instance.isAltPressed) 'Alt',
      if (HardwareKeyboard.instance.isMetaPressed) 'Meta',
    ];
    _state.addKeyEvent('key: ${[...parts, logical.keyLabel].join('+')}');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final corner = widget.corner;
    return Directionality(
      // Self-contained: the HUD does not assume a Directionality/MaterialApp
      // ancestor (the real app provides one, but the HUD must also work when
      // pumped in isolation).
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.loose,
        children: <Widget>[
          Positioned.fill(child: widget.child),
          Positioned.fill(child: _PointerCapture(state: _state)),
          Positioned(
            top: corner == HudCorner.topLeft || corner == HudCorner.topRight ? 16.0 : null,
            bottom: corner == HudCorner.bottomLeft || corner == HudCorner.bottomRight ? 16.0 : null,
            left: corner == HudCorner.topLeft || corner == HudCorner.bottomLeft ? 16.0 : null,
            right: corner == HudCorner.topRight || corner == HudCorner.bottomRight ? 16.0 : null,
            child: IgnorePointer(
              child: _HudPanel(state: _state, corner: corner, speed: widget.speed),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen translucent [Listener] that records pointer events into [state].
class _PointerCapture extends StatelessWidget {
  const _PointerCapture({required this.state});

  final HudState state;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _record(e, 'down ${_buttonLabel(e)}'),
      onPointerUp: (e) => _record(e, 'up ${_buttonLabel(e)}'),
      onPointerHover: (e) => _record(e, 'hover'),
      onPointerMove: (e) => _record(e, 'move'),
      // Mouse wheel / trackpad scroll arrives on desktop as a pointer signal
      // (PointerScrollEvent) — onPointerPanZoom* alone would miss it.
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) {
          return;
        }
        state.setMousePosition(e.position);
        state.addPointerEvent('scroll d(${e.scrollDelta.dx.round()}, ${e.scrollDelta.dy.round()}) @ (${e.position.dx.round()}, ${e.position.dy.round()})');
      },
      onPointerPanZoomStart: (e) => _record(e, 'pan start'),
      onPointerPanZoomUpdate: (e) => _record(e, 'pan'),
      onPointerPanZoomEnd: (e) => _record(e, 'pan end'),
      child: const SizedBox.expand(),
    );
  }

  void _record(PointerEvent event, String action) {
    state.setMousePosition(event.position);
    state.addPointerEvent('mouse: $action @ (${event.position.dx.round()}, ${event.position.dy.round()})');
  }

  /// Human-readable label for the button carried by [event] (`event.buttons`),
  /// e.g. `L` / `R` / `M` instead of a hardcoded assumption.
  String _buttonLabel(PointerEvent event) {
    final buttons = event.buttons;
    if ((buttons & 1) != 0) return 'L';
    if ((buttons & 4) != 0) return 'R';
    if ((buttons & 2) != 0) return 'M';
    return 'L';
  }
}

/// The translucent panel listing the most recent captured events.
class _HudPanel extends StatelessWidget {
  const _HudPanel({required this.state, required this.corner, required this.speed});

  final HudState state;
  final HudCorner corner;
  final double speed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final mouse = state.mousePosition;
        return Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '🐢 slow-motion ×${_formatSpeed(speed)}  ·  HUD: ${corner.name}',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'mouse: ${mouse == null ? '(—, —)' : '(${mouse.dx.round()}, ${mouse.dy.round()})'}',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 4),
              ...state.keyEvents.reversed.map((e) => _EventLine(e, color: Colors.white)),
              const SizedBox(height: 4),
              ...state.pointerEvents.reversed.map((e) => _EventLine(e, color: Colors.white70)),
            ],
          ),
        );
      },
    );
  }
}

/// One monospaced line in the HUD event log.
class _EventLine extends StatelessWidget {
  const _EventLine(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
      ),
    );
  }
}

String _formatSpeed(double speed) => speed == speed.roundToDouble() ? speed.toInt().toString() : speed.toString();
