// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/helpers/slow_motion_hud.dart';

void main() {
  test('HudState trims each channel to maxEvents independently', () {
    final state = HudState(maxEvents: 3);
    state.addKeyEvent('a');
    state.addKeyEvent('b');
    state.addPointerEvent('mouse');
    state.addKeyEvent('c');
    state.addKeyEvent('d');

    expect(state.keyEvents, <String>['b', 'c', 'd']);
    expect(state.pointerEvents, <String>['mouse']);

    state.setMousePosition(const Offset(10, 20));
    expect(state.mousePosition, const Offset(10, 20));

    state.dispose();
  });

  group('SlowMotionHud —', () {
    testWidgets('captures key events with modifier state, cleared on key-up', (tester) async {
      final state = HudState();
      await tester.pumpWidget(SlowMotionHud(state: state, child: const SizedBox.expand()));
      await tester.pump();

      // Plain key.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      expect(state.keyEvents, <String>['key: H']);
      state.keyEvents.clear();

      // Ctrl+S: modifier state comes from the framework, so it is present on
      // the down and gone again after the Ctrl key-up.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(state.keyEvents, <String>['key: Ctrl+S']);
      state.keyEvents.clear();

      // Regression (review blocker): a single key pressed AFTER a released
      // modifier must NOT carry a stale modifier prefix.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(state.keyEvents, <String>['key: A']);

      await tester.pumpWidget(const SizedBox.shrink()); // unmount the HUD
    });

    testWidgets('captures pointer down/up/move and tracks position', (tester) async {
      final state = HudState();
      await tester.pumpWidget(SlowMotionHud(state: state, child: const SizedBox.expand()));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.moveTo(const Offset(30, 40)); // hover
      expect(state.pointerEvents, contains('mouse: hover @ (30, 40)'));
      await gesture.down(const Offset(30, 40));
      expect(state.pointerEvents, contains('mouse: down L @ (30, 40)'));
      await gesture.moveBy(const Offset(30, 40)); // move
      expect(state.pointerEvents, contains('mouse: move @ (60, 80)'));
      await gesture.up();
      expect(state.pointerEvents, contains('mouse: up L @ (60, 80)'));
      expect(state.mousePosition, const Offset(60, 80));

      await tester.pumpWidget(const SizedBox.shrink()); // unmount the HUD
    });

    testWidgets('captures wheel scroll as a pointer signal', (tester) async {
      final state = HudState();
      await tester.pumpWidget(SlowMotionHud(state: state, child: const SizedBox.expand()));
      await tester.pump();

      // On desktop the wheel arrives as a PointerScrollEvent signal; dispatch
      // one through the same test-pointer dispatcher that down/move/up use.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.updateWithCustomEvent(
        const PointerScrollEvent(viewId: 0, timeStamp: Duration.zero, kind: PointerDeviceKind.mouse, position: Offset(12, 34), scrollDelta: Offset(0, -40)),
      );
      expect(state.pointerEvents, contains('scroll d(0, -40) @ (12, 34)'));
      expect(state.mousePosition, const Offset(12, 34));

      await tester.pumpWidget(const SizedBox.shrink()); // unmount the HUD
    });

    testWidgets('owns the timeDilation lifecycle: sets on mount, restores on dispose', (tester) async {
      expect(timeDilation, 1.0);

      await tester.pumpWidget(const SlowMotionHud(speed: 7, child: SizedBox.expand()));
      await tester.pump();
      expect(timeDilation, 7.0);

      await tester.pumpWidget(const SizedBox.shrink()); // unmount the HUD
      await tester.pump();
      expect(timeDilation, 1.0);
    });

    testWidgets('observes taps without intercepting them (app still receives the event)', (tester) async {
      final state = HudState();
      var taps = 0;
      await tester.pumpWidget(
        SlowMotionHud(
          state: state,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const SizedBox.expand()),
        ),
      );
      await tester.pump();

      await tester.tapAt(const Offset(100, 100));
      await tester.pump();

      expect(taps, 1); // the app underneath got the tap
      // ...and the HUD observed the same tap without stealing it.
      expect(state.pointerEvents, contains('mouse: down L @ (100, 100)'));
      expect(state.pointerEvents, contains('mouse: up L @ (100, 100)'));

      await tester.pumpWidget(const SizedBox.shrink()); // unmount the HUD
    });
  });
}
