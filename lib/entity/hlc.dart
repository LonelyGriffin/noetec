// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:math';

final class Hlc implements Comparable<Hlc> {
  final int physicalMs;
  final int counter;
  final String deviceId;

  const Hlc({
    required this.physicalMs,
    required this.counter,
    required this.deviceId,
  });

  factory Hlc.now(Hlc? last, String deviceId) {
    final wallMs = DateTime.now().millisecondsSinceEpoch;
    final physical = max(wallMs, last?.physicalMs ?? 0);
    int count;
    if (physical == (last?.physicalMs ?? -1)) {
      count = last!.counter + 1;
    } else {
      count = 0;
    }
    if (count > 0xFFFF) {
      return Hlc(physicalMs: physical + 1, counter: 0, deviceId: deviceId);
    }
    return Hlc(physicalMs: physical, counter: count, deviceId: deviceId);
  }

  factory Hlc.receive(Hlc remote, Hlc? last, String deviceId) {
    final wallMs = DateTime.now().millisecondsSinceEpoch;
    final lastMs = last?.physicalMs ?? 0;
    final physical = _max3(wallMs, remote.physicalMs, lastMs);

    int count;
    if (physical == lastMs && physical == remote.physicalMs) {
      count = max(last?.counter ?? 0, remote.counter) + 1;
    } else if (physical == lastMs) {
      count = (last?.counter ?? 0) + 1;
    } else if (physical == remote.physicalMs) {
      count = remote.counter + 1;
    } else {
      count = 0;
    }
    if (count > 0xFFFF) {
      return Hlc(physicalMs: physical + 1, counter: 0, deviceId: deviceId);
    }
    return Hlc(physicalMs: physical, counter: count, deviceId: deviceId);
  }

  String toKey() =>
      '$physicalMs-${counter.toRadixString(16).padLeft(4, '0')}-$deviceId';

  factory Hlc.fromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) throw FormatException('Invalid HLC key: $key');
    return Hlc(
      physicalMs: int.parse(parts[0]),
      counter: int.parse(parts[1], radix: 16),
      deviceId: parts[2],
    );
  }

  @override
  int compareTo(Hlc other) {
    var result = physicalMs.compareTo(other.physicalMs);
    if (result != 0) return result;
    result = counter.compareTo(other.counter);
    if (result != 0) return result;
    return deviceId.compareTo(other.deviceId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          physicalMs == other.physicalMs &&
          counter == other.counter &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(physicalMs, counter, deviceId);

  @override
  String toString() => toKey();

  static int _max3(int a, int b, int c) => max(a, max(b, c));

  static String truncateDeviceId(String fullUuid) =>
      fullUuid.replaceAll('-', '').substring(0, 8);
}
