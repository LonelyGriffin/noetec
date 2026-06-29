import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';

void main() {
  group('DeviceIdentity —', () {
    test('toJson/fromJson roundtrip', () {
      final identity = DeviceIdentity(
        uuid: 'abc-123',
        name: 'Desktop',
        createdAt: DateTime(2026, 6, 1),
        lastHlc: '1705312200000-0001-a1b2c3d4',
        publicKey: 'public-key-base64',
      );

      final json = identity.toJson();
      final restored = DeviceIdentity.fromJson(json);

      expect(restored.uuid, identity.uuid);
      expect(restored.name, identity.name);
      expect(restored.lastHlc, identity.lastHlc);
      expect(restored.publicKey, identity.publicKey);
    });

    test('withLastHlc creates new instance with updated lastHlc', () {
      final identity = DeviceIdentity(
        uuid: 'test',
        name: 'test',
        createdAt: DateTime.now(),
        lastHlc: null,
        publicKey: 'key123',
      );

      final updated = identity.withLastHlc('1705312200000-0001-a1b2c3d4');

      expect(updated.lastHlc, '1705312200000-0001-a1b2c3d4');
      expect(identity.lastHlc, isNull);
      expect(updated.publicKey, 'key123');
    });
  });
}
