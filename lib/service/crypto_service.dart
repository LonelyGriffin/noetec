// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

abstract interface class ICryptoService {
  Future<({String publicKeyBase64, String privateKeyBase64})>
  generateDeviceKeyPair();
}

class CryptoServiceImpl implements ICryptoService {
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<({String publicKeyBase64, String privateKeyBase64})>
  generateDeviceKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final publicKeyBytes = publicKey.bytes;
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    return (
      publicKeyBase64: base64Encode(Uint8List.fromList(publicKeyBytes)),
      privateKeyBase64: base64Encode(Uint8List.fromList(privateKeyBytes)),
    );
  }
}
