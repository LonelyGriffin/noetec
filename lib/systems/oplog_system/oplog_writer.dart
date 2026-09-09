// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';

class OpLogWriter {
  const OpLogWriter(this._fs, this._vaultRootPath, this._serializer, {OpLogSigner? signer, String? vaultId, String? devicePublicKeyBase64Url})
    : _signer = signer,
      _vaultId = vaultId,
      _devicePublicKeyBase64Url = devicePublicKeyBase64Url;

  final IFileSystemService _fs;
  final String _vaultRootPath;
  final OpLogSerializer _serializer;

  /// When set, every appended entry is signed first (sync-security.md §2.3).
  /// When `null` (e.g. low-level IO tests) entries are written unsigned,
  /// preserving the historical behavior.
  final OpLogSigner? _signer;

  /// Vault id and the authoring device's base64url public key, supplied to the
  /// signer per append. Both are required when [signer] is non-null.
  final String? _vaultId;
  final String? _devicePublicKeyBase64Url;

  Future<void> append(String relativePath, OpLogEntry entry) async {
    final dirPath = _oplogDir(relativePath);
    if (!await _fs.directoryExists(dirPath)) {
      await _fs.createDirectory(dirPath);
    }

    final filePath = _oplogFilePath(relativePath, entry.deviceId);

    // Sign before encoding so the signature (and first-entry pubKey) are part
    // of the serialized line. The signing input is the entry's wire form, so
    // the bytes signed are byte-identical to the bytes stored.
    var toWrite = entry;
    final signer = _signer;
    if (signer != null) {
      toWrite = await signer.sign(entry, relativePath, vaultId: _vaultId!, devicePublicKeyBase64Url: _devicePublicKeyBase64Url!);
    }

    final jsonLine = _serializer.encode(toWrite);
    await _fs.appendToFile(filePath, '$jsonLine\n');
  }

  String _oplogDir(String relativePath) {
    return '$_vaultRootPath/.sync/$relativePath';
  }

  String _oplogFilePath(String relativePath, String deviceId) {
    final dir = _oplogDir(relativePath);
    return '$dir/$deviceId.oplog.jsonl';
  }
}
