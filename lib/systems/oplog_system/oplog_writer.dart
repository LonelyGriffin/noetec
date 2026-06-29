// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';

class OpLogWriter {
  const OpLogWriter(this._fs, this._vaultRootPath, this._serializer);

  final IFileSystemService _fs;
  final String _vaultRootPath;
  final OpLogSerializer _serializer;

  Future<void> append(String relativePath, OpLogEntry entry) async {
    final dirPath = _oplogDir(relativePath);
    if (!await _fs.directoryExists(dirPath)) {
      await _fs.createDirectory(dirPath);
    }

    final filePath = _oplogFilePath(relativePath, entry.deviceId);
    final jsonLine = _serializer.encode(entry);
    await _fs.appendToFile(filePath, '$jsonLine\n');
  }

  String _oplogDir(String relativePath) {
    final encoded = Uri.encodeComponent(relativePath);
    return '$_vaultRootPath/.sync/pages/$encoded';
  }

  String _oplogFilePath(String relativePath, String deviceId) {
    final dir = _oplogDir(relativePath);
    return '$dir/$deviceId.oplog.jsonl';
  }
}
