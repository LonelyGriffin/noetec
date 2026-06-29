// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:convert';

import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/systems/oplog_system/state_reconstruction_engine.dart';
import 'package:noetec/systems/sync_system/merge_engine.dart';
import 'package:path/path.dart' as p;

final class PersistentConflictEntry {
  final String relativePath;
  final List<BlockConflict> conflicts;
  final Hlc ourHead;
  final Hlc theirHead;
  final DateTime detectedAt;

  const PersistentConflictEntry({
    required this.relativePath,
    required this.conflicts,
    required this.ourHead,
    required this.theirHead,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
    'relative_path': relativePath,
    'conflicts': conflicts.map(_blockConflictToJson).toList(),
    'our_head': ourHead.toKey(),
    'their_head': theirHead.toKey(),
    'detected_at': detectedAt.toIso8601String(),
  };

  factory PersistentConflictEntry.fromJson(Map<String, dynamic> json) =>
      PersistentConflictEntry(
        relativePath: json['relative_path'] as String,
        conflicts: (json['conflicts'] as List)
            .map((c) => _blockConflictFromJson(c as Map<String, dynamic>))
            .toList(),
        ourHead: Hlc.fromKey(json['our_head'] as String),
        theirHead: Hlc.fromKey(json['their_head'] as String),
        detectedAt: DateTime.parse(json['detected_at'] as String),
      );
}

class ConflictStore {
  ConflictStore(this._fileSystem);

  final IFileSystemService _fileSystem;
  final List<PersistentConflictEntry> _entries = [];

  List<PersistentConflictEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  Future<void> load(String vaultRootPath) async {
    final filePath = _conflictsPath(vaultRootPath);
    if (!await _fileSystem.fileExists(filePath)) return;

    final content = await _fileSystem.readFile(filePath);
    final data = jsonDecode(content) as Map<String, dynamic>;
    final list = data['conflicts'] as List;
    _entries
      ..clear()
      ..addAll(
        list.map(
          (e) => PersistentConflictEntry.fromJson(e as Map<String, dynamic>),
        ),
      );
  }

  Future<void> save(String vaultRootPath) async {
    final filePath = _conflictsPath(vaultRootPath);
    final data = {'conflicts': _entries.map((e) => e.toJson()).toList()};
    await _fileSystem.writeFile(filePath, jsonEncode(data));
  }

  void addConflicts(
    String relativePath,
    List<BlockConflict> conflicts,
    Hlc ourHead,
    Hlc theirHead,
  ) {
    _entries.removeWhere((e) => e.relativePath == relativePath);
    _entries.add(
      PersistentConflictEntry(
        relativePath: relativePath,
        conflicts: conflicts,
        ourHead: ourHead,
        theirHead: theirHead,
        detectedAt: DateTime.now(),
      ),
    );
  }

  void removeBlockConflict(String relativePath, String blockId) {
    final entry = getByPath(relativePath);
    if (entry == null) return;

    final remaining = entry.conflicts
        .where((c) => c.blockId != blockId)
        .toList();

    if (remaining.isEmpty) {
      _entries.remove(entry);
    } else {
      final updated = PersistentConflictEntry(
        relativePath: entry.relativePath,
        conflicts: remaining,
        ourHead: entry.ourHead,
        theirHead: entry.theirHead,
        detectedAt: entry.detectedAt,
      );
      final idx = _entries.indexOf(entry);
      _entries[idx] = updated;
    }
  }

  PersistentConflictEntry? getByPath(String relativePath) {
    for (final entry in _entries) {
      if (entry.relativePath == relativePath) return entry;
    }
    return null;
  }

  bool hasConflicts(String relativePath) => getByPath(relativePath) != null;

  static String _conflictsPath(String vaultRootPath) =>
      p.join(vaultRootPath, '.noetec', 'conflicts.json');
}

Map<String, dynamic> _blockConflictToJson(BlockConflict conflict) {
  switch (conflict) {
    case ContentConflict():
      return {
        'type': 'content',
        'block_id': conflict.blockId,
        'ours': _reconstructedBlockToJson(conflict.ours),
        'theirs': _reconstructedBlockToJson(conflict.theirs),
      };
    case DeleteModifyConflict():
      return {
        'type': 'delete_modify',
        'block_id': conflict.blockId,
        'modified_block': _reconstructedBlockToJson(conflict.modifiedBlock),
        'deleted_by_us': conflict.deletedByUs,
      };
  }
}

BlockConflict _blockConflictFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  switch (type) {
    case 'content':
      return ContentConflict(
        blockId: json['block_id'] as String,
        ours: _reconstructedBlockFromJson(json['ours'] as Map<String, dynamic>),
        theirs: _reconstructedBlockFromJson(
          json['theirs'] as Map<String, dynamic>,
        ),
      );
    case 'delete_modify':
      return DeleteModifyConflict(
        blockId: json['block_id'] as String,
        modifiedBlock: _reconstructedBlockFromJson(
          json['modified_block'] as Map<String, dynamic>,
        ),
        deletedByUs: json['deleted_by_us'] as bool,
      );
    default:
      throw FormatException('Unknown conflict type: $type');
  }
}

Map<String, dynamic> _reconstructedBlockToJson(ReconstructedBlock block) => {
  'block_id': block.blockId,
  'text': block.segmentText,
};

ReconstructedBlock _reconstructedBlockFromJson(Map<String, dynamic> json) {
  final text = json['text'] as String;
  return ReconstructedBlock(
    blockId: json['block_id'] as String,
    segments: text.isEmpty ? const [] : [TextSegment(text: text)],
  );
}
