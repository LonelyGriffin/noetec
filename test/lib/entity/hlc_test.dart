import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';

void main() {
  group('Hlc —', () {
    test('now() creates HLC with current wall time', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final hlc = Hlc.now(null, 'dev1');
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(hlc.physicalMs, greaterThanOrEqualTo(before));
      expect(hlc.physicalMs, lessThanOrEqualTo(after));
      expect(hlc.counter, 0);
      expect(hlc.deviceId, 'dev1');
    });

    test('now() increments counter when physicalMs matches last', () {
      final first = Hlc.now(null, 'dev1');
      final second = Hlc.now(first, 'dev1');

      expect(second, greaterThan(first));
      if (second.physicalMs == first.physicalMs) {
        expect(second.counter, first.counter + 1);
      }
    });

    test('receive() result is greater than both remote and last', () {
      final localLast = Hlc.now(null, 'dev1');
      final remote = Hlc(
        physicalMs: localLast.physicalMs + 1000,
        counter: 5,
        deviceId: 'dev2',
      );
      final received = Hlc.receive(remote, localLast, 'dev1');

      expect(received, greaterThan(remote));
      expect(received, greaterThan(localLast));
      expect(received.deviceId, 'dev1');
    });

    test('toKey/fromKey roundtrip', () {
      const hlc = Hlc(
        physicalMs: 1705312200000,
        counter: 42,
        deviceId: 'a1b2c3d4',
      );
      final key = hlc.toKey();
      final restored = Hlc.fromKey(key);

      expect(restored, equals(hlc));
    });

    test('compareTo orders by physicalMs, then counter, then deviceId', () {
      const a = Hlc(physicalMs: 100, counter: 0, deviceId: 'aaa');
      const b = Hlc(physicalMs: 100, counter: 1, deviceId: 'aaa');
      const c = Hlc(physicalMs: 101, counter: 0, deviceId: 'aaa');
      const d = Hlc(physicalMs: 100, counter: 0, deviceId: 'bbb');

      expect(a.compareTo(b), lessThan(0));
      expect(a.compareTo(c), lessThan(0));
      expect(a.compareTo(d), lessThan(0));
    });

    test('fromKey throws on malformed key', () {
      expect(() => Hlc.fromKey('bad'), throwsFormatException);
      expect(() => Hlc.fromKey('a-b'), throwsFormatException);
    });
  });
}
