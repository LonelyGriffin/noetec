// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:path/path.dart' as p;

Future<void> expectDeviceHasPublicKey(String vaultPath) async {
  final deviceFile = File(p.join(vaultPath, '.noetec', 'device.json'));
  final content =
      json.decode(await deviceFile.readAsString()) as Map<String, dynamic>;
  expect(content['public_key'], isNotNull);
  expect(content['public_key'] as String, isNotEmpty);
}

Future<String> readPublicKeyFromDevice(String vaultPath) async {
  final deviceFile = File(p.join(vaultPath, '.noetec', 'device.json'));
  final content =
      json.decode(await deviceFile.readAsString()) as Map<String, dynamic>;
  return content['public_key'] as String;
}

Future<String> readVaultId(String vaultPath) async {
  final vaultFile = File(p.join(vaultPath, '.noetec', 'vault.json'));
  final content =
      json.decode(await vaultFile.readAsString()) as Map<String, dynamic>;
  return content['id'] as String;
}

Future<String?> readDevicePrivateKeyFromStore(String vaultPath) async {
  final vaultId = await readVaultId(vaultPath);
  final keyStore = GetIt.instance<ISecureKeyStore>();
  return keyStore.readDevicePrivateKey(vaultId);
}
