// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Corner of the screen the HUD panel is pinned to.
enum HudCorner { topLeft, topRight, bottomLeft, bottomRight }

/// The most recent events captured for the HUD.
///
/// Backed by a [ValueNotifier] so the panel rebuilds reactively — no
/// `setState` anywhere, consistent with the project's reactive conventions.
class HudState extends ValueNotifier<List<String>> {
  HudState({this.maxEvents = 12}) : super(const <String>[]);

  /// How many recent events the panel keeps.
  final int maxEvents;

  /// Last known pointer position, or `null` before the first pointer event.
  Offset? mousePosition;

  /// Modifier keys currently held down (Ctrl / Alt / Shift / Meta).
  final Set<LogicalKeyboardKey> modifierKeys = <LogicalKeyboardKey>{};

  /// Records [event], trimming the log to [maxEvents] entries.
  void addEvent(String event) {
    final list = <String>[...value, event];
    if (list.length > maxEvents) {
      list.removeRange(0, list.length - maxEvents);
    }
    value = list;
  }

  /// Resets all captured state (use when tearing the HUD down between tests).
  void reset() {
    mousePosition = null;
    modifierKeys.clear();
    value = const <String>[];
  }

  static bool _isModifier(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
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

  /// Records key-down events. Never returns `true` so the event is NOT
  /// marked as handled — the app still receives it (text fields, shortcuts).
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final logical = event.logicalKey;
    if (HudState._isModifier(logical)) {
      // Modifier keys only update the combo state; they are not logged on
      // their own (keeps the log readable: "key: Ctrl+S", not "key: Ctrl"
      // followed by "key: Ctrl+S").
      _state.modifierKeys.add(logical);
      return false;
    }
    final parts = <String>[
      if (_state.modifierKeys.contains(LogicalKeyboardKey.controlLeft) || _state.modifierKeys.contains(LogicalKeyboardKey.controlRight)) 'Ctrl',
      if (_state.modifierKeys.contains(LogicalKeyboardKey.altLeft) || _state.modifierKeys.contains(LogicalKeyboardKey.altRight)) 'Alt',
      if (_state.modifierKeys.contains(LogicalKeyboardKey.shiftLeft) || _state.modifierKeys.contains(LogicalKeyboardKey.shiftRight)) 'Shift',
      if (_state.modifierKeys.contains(LogicalKeyboardKey.metaLeft) || _state.modifierKeys.contains(LogicalKeyboardKey.metaRight)) 'Meta',
    ];
    _state.addEvent('key: ${[...parts, logical.keyLabel].join('+')}');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final corner = widget.corner;
    return Directionality(
      // Self-contained: the HUD is self-sufficient and does not assume a
      // Directionality/MaterialApp ancestor (the real app provides one, but
      // the HUD must also work when pumped in isolation).
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
      onPointerDown: (e) => _record(e, 'down L'),
      onPointerUp: (e) => _record(e, 'up L'),
      onPointerHover: (e) => _record(e, 'hover'),
      onPointerMove: (e) => _record(e, 'move'),
      onPointerPanZoomStart: (e) => _record(e, 'pan start'),
      onPointerPanZoomUpdate: (e) => _record(e, 'pan'),
      onPointerPanZoomEnd: (e) => _record(e, 'pan end'),
      child: const SizedBox.expand(),
    );
  }

  void _record(PointerEvent event, String action) {
    state.mousePosition = event.position;
    state.addEvent('mouse: $action @ (${event.position.dx.round()}, ${event.position.dy.round()})');
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
          width: 260,
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
              ...state.value.reversed.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    e,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatSpeed(double speed) => speed == speed.roundToDouble() ? speed.toInt().toString() : speed.toString();
