// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';

class OpLogReader {
  const OpLogReader(this._fs, this._vaultRootPath, this._serializer);

  final IFileSystemService _fs;
  final String _vaultRootPath;
  final OpLogSerializer _serializer;

  Future<List<OpLogEntry>> readDeviceLog(
    String relativePath,
    String deviceUuid,
  ) async {
    final filePath = _oplogFilePath(relativePath, deviceUuid);
    if (!await _fs.fileExists(filePath)) return [];

    final content = await _fs.readFile(filePath);
    return _parseLines(content);
  }

  Future<Map<String, List<OpLogEntry>>> readAllLogs(String relativePath) async {
    final deviceUuids = await getDeviceUuids(relativePath);
    final result = <String, List<OpLogEntry>>{};
    for (final uuid in deviceUuids) {
      result[uuid] = await readDeviceLog(relativePath, uuid);
    }
    return result;
  }

  Future<List<String>> getDeviceUuids(String relativePath) async {
    final dirPath = _oplogDir(relativePath);
    if (!await _fs.directoryExists(dirPath)) return [];

    final entries = await _fs.listDirectory(dirPath);
    return entries
        .where((e) => !e.isDirectory && e.name.endsWith('.oplog.jsonl'))
        .map((e) {
          final name = e.name;
          return name.substring(0, name.length - '.oplog.jsonl'.length);
        })
        .toList();
  }

  List<OpLogEntry> _parseLines(String content) {
    final entries = <OpLogEntry>[];
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        entries.add(_serializer.decode(line));
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  String _oplogDir(String relativePath) {
    return '$_vaultRootPath/.sync/$relativePath';
  }

  String _oplogFilePath(String relativePath, String deviceId) {
    final dir = _oplogDir(relativePath);
    return '$dir/$deviceId.oplog.jsonl';
  }
}
