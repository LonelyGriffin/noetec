// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:convert';

import 'package:canonical_json/canonical_json.dart' as cj;
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

class OpLogSerializer {
  const OpLogSerializer();

  /// Builds the Phase-1 signing input per sync-security.md §2.2:
  ///
  /// ```text
  /// signingInput = canonicalJson(entryWithoutSignature) + documentPath
  /// ```
  ///
  /// [entryWithoutSignature] is the entry's wire representation (snake_case
  /// keys) **without** the `signature` field — i.e. [OpLogEntry.toWireMap],
  /// which already includes `pubKey` when present — canonicalized with the
  /// OLPC Canonical JSON encoding. [documentPath] is the page path relative
  /// to the vault root, no extension, `/` separators (e.g. `notes/ideas`),
  /// appended with no separator.
  ///
  /// The result is a [List<int>] (UTF-8 bytes) ready to be passed to
  /// `ICryptoService.sign` / `ICryptoService.verify`.
  List<int> signingInput(OpLogEntry entryWithoutSignature, String documentPath) {
    final canonical = cj.canonicalJson.encode(entryWithoutSignature.toWireMap());
    return [...canonical, ...utf8.encode(documentPath)];
  }

  String encode(OpLogEntry entry) {
    final map = entry.toWireMap();
    if (entry.signature != null) {
      map['signature'] = entry.signature;
    }
    return jsonEncode(map);
  }

  OpLogEntry decode(String jsonLine) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonLine);
    } on FormatException catch (e) {
      throw FormatException('Invalid oplog JSON: $e', jsonLine);
    }

    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Oplog entry is not a JSON object', jsonLine);
    }

    final hlcRaw = decoded['hlc'];
    if (hlcRaw is! String) {
      throw FormatException('Missing or invalid "hlc"', jsonLine);
    }
    final typeRaw = decoded['type'];
    if (typeRaw is! String) {
      throw FormatException('Missing or invalid "type"', jsonLine);
    }
    final deviceRaw = decoded['device'];
    if (deviceRaw is! String) {
      throw FormatException('Missing or invalid "device"', jsonLine);
    }

    final type = OpEntryTypeWire.fromWire(typeRaw);

    final parentRaw = decoded['parent'];
    final parentBRaw = decoded['parent_b'];

    List<BlockOp>? blockOps;
    final rawBlockOps = decoded['block_ops'];
    if (rawBlockOps is List) {
      blockOps = rawBlockOps.map((e) => BlockOp.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }

    FileOp? fileOp;
    final rawFileOp = decoded['file_op'];
    if (rawFileOp is Map) {
      fileOp = FileOp.fromJson(Map<String, dynamic>.from(rawFileOp));
    }

    return OpLogEntry(
      version: (decoded['v'] as int?) ?? 1,
      hlc: Hlc.fromKey(hlcRaw),
      parent: parentRaw is String ? Hlc.fromKey(parentRaw) : null,
      parentB: parentBRaw is String ? Hlc.fromKey(parentBRaw) : null,
      type: type,
      blockOps: blockOps,
      fileOp: fileOp,
      fileHash: decoded['file_hash'] as String?,
      deviceId: deviceRaw,
      signature: decoded['signature'] as String?,
      pubKey: decoded['pubKey'] as String?,
    );
  }

  Map<String, dynamic> segmentToJson(TextSegment segment) {
    if (segment is LinkSegment) {
      return {'text': segment.text, 'format': 0, 'url': segment.url};
    }
    if (segment is FormattedSegment) {
      return {'text': segment.text, 'format': segment.format.flags};
    }
    return {'text': segment.text, 'format': 0};
  }

  TextSegment segmentFromJson(Map<String, dynamic> json) {
    final text = (json['text'] as String?) ?? '';
    final url = json['url'] as String?;
    if (url != null) {
      return LinkSegment(text: text, url: url);
    }
    final format = (json['format'] as int?) ?? 0;
    if (format == 0) {
      return TextSegment(text: text);
    }
    return FormattedSegment(text: text, format: TextFormat.fromFlags(format));
  }
}
