import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> expectVaultJsonValid(
  String vaultPath, {
  required String name,
}) async {
  final vaultFile = File(p.join(vaultPath, '.noetec', 'vault.json'));
  expect(await vaultFile.exists(), isTrue);
  final content =
      json.decode(await vaultFile.readAsString()) as Map<String, dynamic>;
  expect(content['name'], equals(name));
  expect(content['rootPath'], equals(vaultPath));
}

Future<void> expectDeviceIdentityExists(String vaultPath) async {
  expect(
    await File(p.join(vaultPath, '.noetec', 'device.json')).exists(),
    isTrue,
  );
}
