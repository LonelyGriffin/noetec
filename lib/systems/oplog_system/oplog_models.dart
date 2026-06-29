// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';

sealed class BlockOp {
  const BlockOp();

  Map<String, dynamic> toJson();

  static BlockOp fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'insert':
        return BlockInsert.fromJson(json);
      case 'delete':
        return BlockDelete.fromJson(json);
      case 'update':
        return BlockUpdate.fromJson(json);
      case 'move':
        return BlockMove.fromJson(json);
      default:
        throw FormatException('Unknown BlockOp type: $type');
    }
  }
}

final class BlockInsert extends BlockOp {
  final String blockId;
  final String? afterBlockId;
  final List<TextSegment> segments;

  const BlockInsert({
    required this.blockId,
    required this.afterBlockId,
    required this.segments,
  });

  factory BlockInsert.fromJson(Map<String, dynamic> json) {
    return BlockInsert(
      blockId: json['blockId'] as String,
      afterBlockId: json['afterBlockId'] as String?,
      segments: (json['segments'] as List)
          .map((s) => _segmentFromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'insert',
    'blockId': blockId,
    'afterBlockId': afterBlockId,
    'segments': segments.map(_segmentToJson).toList(),
  };
}

final class BlockDelete extends BlockOp {
  final String blockId;

  const BlockDelete({required this.blockId});

  factory BlockDelete.fromJson(Map<String, dynamic> json) {
    return BlockDelete(blockId: json['blockId'] as String);
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'delete', 'blockId': blockId};
}

final class BlockUpdate extends BlockOp {
  final String blockId;
  final List<TextSegment> segments;

  const BlockUpdate({required this.blockId, required this.segments});

  factory BlockUpdate.fromJson(Map<String, dynamic> json) {
    return BlockUpdate(
      blockId: json['blockId'] as String,
      segments: (json['segments'] as List)
          .map((s) => _segmentFromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'update',
    'blockId': blockId,
    'segments': segments.map(_segmentToJson).toList(),
  };
}

final class BlockMove extends BlockOp {
  final String blockId;
  final String? afterBlockId;

  const BlockMove({required this.blockId, required this.afterBlockId});

  factory BlockMove.fromJson(Map<String, dynamic> json) {
    return BlockMove(
      blockId: json['blockId'] as String,
      afterBlockId: json['afterBlockId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'move',
    'blockId': blockId,
    'afterBlockId': afterBlockId,
  };
}

sealed class FileOp {
  const FileOp();

  Map<String, dynamic> toJson();

  static FileOp fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'create':
        return FileCreateOp.fromJson(json);
      case 'delete':
        return const FileDeleteOp();
      case 'rename':
        return FileRenameOp.fromJson(json);
      default:
        throw FormatException('Unknown FileOp type: $type');
    }
  }
}

final class FileCreateOp extends FileOp {
  final String pageId;
  final List<TextBlockSnapshot> initialBlocks;

  const FileCreateOp({required this.pageId, required this.initialBlocks});

  factory FileCreateOp.fromJson(Map<String, dynamic> json) {
    return FileCreateOp(
      pageId: json['pageId'] as String,
      initialBlocks: (json['initialBlocks'] as List)
          .map((b) => TextBlockSnapshot.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'create',
    'pageId': pageId,
    'initialBlocks': initialBlocks.map((b) => b.toJson()).toList(),
  };
}

final class FileDeleteOp extends FileOp {
  const FileDeleteOp();

  @override
  Map<String, dynamic> toJson() => {'type': 'delete'};
}

final class FileRenameOp extends FileOp {
  final String oldPath;
  final String newPath;

  const FileRenameOp({required this.oldPath, required this.newPath});

  factory FileRenameOp.fromJson(Map<String, dynamic> json) {
    return FileRenameOp(
      oldPath: json['oldPath'] as String,
      newPath: json['newPath'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rename',
    'oldPath': oldPath,
    'newPath': newPath,
  };
}

final class TextBlockSnapshot {
  final String blockId;
  final String? afterBlockId;
  final List<TextSegment> segments;

  const TextBlockSnapshot({
    required this.blockId,
    required this.afterBlockId,
    required this.segments,
  });

  factory TextBlockSnapshot.fromJson(Map<String, dynamic> json) {
    return TextBlockSnapshot(
      blockId: json['blockId'] as String,
      afterBlockId: json['afterBlockId'] as String?,
      segments: (json['segments'] as List)
          .map((s) => _segmentFromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'blockId': blockId,
    'afterBlockId': afterBlockId,
    'segments': segments.map(_segmentToJson).toList(),
  };
}

enum OpEntryType {
  fileCreate,
  fileDelete,
  fileRename,
  edit,
  save,
  externalEdit,
  merge,
}

extension OpEntryTypeWire on OpEntryType {
  String get wireValue {
    switch (this) {
      case OpEntryType.fileCreate:
        return 'file_create';
      case OpEntryType.fileDelete:
        return 'file_delete';
      case OpEntryType.fileRename:
        return 'file_rename';
      case OpEntryType.edit:
        return 'edit';
      case OpEntryType.save:
        return 'save';
      case OpEntryType.externalEdit:
        return 'external_edit';
      case OpEntryType.merge:
        return 'merge';
    }
  }

  static OpEntryType fromWire(String value) {
    switch (value) {
      case 'file_create':
        return OpEntryType.fileCreate;
      case 'file_delete':
        return OpEntryType.fileDelete;
      case 'file_rename':
        return OpEntryType.fileRename;
      case 'edit':
        return OpEntryType.edit;
      case 'save':
        return OpEntryType.save;
      case 'external_edit':
        return OpEntryType.externalEdit;
      case 'merge':
        return OpEntryType.merge;
      default:
        throw FormatException('Unknown OpEntryType: $value');
    }
  }
}

final class OpLogEntry {
  final int version;
  final Hlc hlc;
  final Hlc? parent;
  final Hlc? parentB;
  final OpEntryType type;
  final List<BlockOp>? blockOps;
  final FileOp? fileOp;
  final String? fileHash;
  final String deviceId;

  const OpLogEntry({
    required this.version,
    required this.hlc,
    required this.parent,
    required this.parentB,
    required this.type,
    required this.blockOps,
    required this.fileOp,
    required this.fileHash,
    required this.deviceId,
  });

  String get hlcKey => hlc.toKey();

  Map<String, dynamic> toJson() => {
    'version': version,
    'hlc': hlc.toKey(),
    if (parent != null) 'parent': parent!.toKey(),
    if (parentB != null) 'parentB': parentB!.toKey(),
    'type': type.name,
    if (blockOps != null)
      'blockOps': blockOps!.map((op) => op.toJson()).toList(),
    if (fileOp != null) 'fileOp': fileOp!.toJson(),
    if (fileHash != null) 'fileHash': fileHash,
    'deviceId': deviceId,
  };

  factory OpLogEntry.fromJson(Map<String, dynamic> json) {
    return OpLogEntry(
      version: json['version'] as int,
      hlc: Hlc.fromKey(json['hlc'] as String),
      parent: json['parent'] != null
          ? Hlc.fromKey(json['parent'] as String)
          : null,
      parentB: json['parentB'] != null
          ? Hlc.fromKey(json['parentB'] as String)
          : null,
      type: OpEntryType.values.firstWhere((t) => t.name == json['type']),
      blockOps: json['blockOps'] != null
          ? (json['blockOps'] as List)
                .map((op) => BlockOp.fromJson(op as Map<String, dynamic>))
                .toList()
          : null,
      fileOp: json['fileOp'] != null
          ? FileOp.fromJson(json['fileOp'] as Map<String, dynamic>)
          : null,
      fileHash: json['fileHash'] as String?,
      deviceId: json['deviceId'] as String,
    );
  }
}

Map<String, dynamic> _segmentToJson(TextSegment segment) {
  if (segment is FormattedSegment) {
    return {
      'type': 'formatted',
      'text': segment.text,
      'format': segment.format.flags,
    };
  } else if (segment is LinkSegment) {
    return {'type': 'link', 'text': segment.text, 'url': segment.url};
  } else {
    return {'type': 'plain', 'text': segment.text};
  }
}

TextSegment _segmentFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  switch (type) {
    case 'formatted':
      return FormattedSegment(
        text: json['text'] as String,
        format: TextFormat.fromFlags(json['format'] as int),
      );
    case 'link':
      return LinkSegment(
        text: json['text'] as String,
        url: json['url'] as String,
      );
    default:
      return TextSegment(text: json['text'] as String);
  }
}
