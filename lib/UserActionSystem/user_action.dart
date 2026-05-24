// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:noetec/DocumentSystem/document_block.dart';

@immutable
sealed class UserAction {
  const UserAction();

  Map<String, dynamic> toJson();

  static UserAction fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String?) {
      'ClickOnTextBlock' => ClickOnTextBlock.fromJson(json),
      'ChangeTextSection' => ChangeTextSection.fromJson(json),
      'SplitTextBlock' => SplitTextBlock.fromJson(json),
      _ => throw ArgumentError('Unknown action type: ${json['type']}'),
    };
  }
}

/// Fired when the user edits text inside a block.
///
/// [newSegments] contains the fully recomputed segment list (formatting
/// preserved by the diff algorithm in UserRawTextInputService).
/// [newSegmentIndex] and [newOffset] describe where the cursor should be
/// placed after the edit.
@immutable
class ChangeTextSection extends UserAction {
  final String documentId;
  final String blockId;
  final List<TextSegment> newSegments;
  final int newSegmentIndex;
  final int newOffset;

  const ChangeTextSection({
    required this.documentId,
    required this.blockId,
    required this.newSegments,
    required this.newSegmentIndex,
    required this.newOffset,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ChangeTextSection',
    'documentId': documentId,
    'blockId': blockId,
    'newSegmentIndex': newSegmentIndex,
    'newOffset': newOffset,
    // segments are not trivially serialisable — omit for logging
  };

  factory ChangeTextSection.fromJson(Map<String, dynamic> json) {
    // Full deserialization is not needed for the prototype (used for logging
    // only). Throw to avoid silent data loss.
    throw UnimplementedError('ChangeTextSection.fromJson is not implemented');
  }
}

/// Fired when the user presses Enter inside a block.
///
/// The block identified by [blockId] is split at [splitFlatOffset]:
/// text before the offset stays in the current block, text from the offset
/// onwards moves to a new block inserted immediately after.
@immutable
class SplitTextBlock extends UserAction {
  final String documentId;
  final String blockId;
  final int splitFlatOffset;

  const SplitTextBlock({
    required this.documentId,
    required this.blockId,
    required this.splitFlatOffset,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SplitTextBlock',
    'documentId': documentId,
    'blockId': blockId,
    'splitFlatOffset': splitFlatOffset,
  };

  factory SplitTextBlock.fromJson(Map<String, dynamic> json) {
    return SplitTextBlock(
      documentId: json['documentId'] as String,
      blockId: json['blockId'] as String,
      splitFlatOffset: json['splitFlatOffset'] as int,
    );
  }
}

@immutable
class ClickOnTextBlock extends UserAction {
  final String documentId;
  final String blockId;
  final int segmentIndex;
  final int offset;

  const ClickOnTextBlock({
    required this.documentId,
    required this.blockId,
    required this.segmentIndex,
    required this.offset,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ClickOnTextBlock',
    'documentId': documentId,
    'blockId': blockId,
    'segmentIndex': segmentIndex,
    'offset': offset,
  };

  factory ClickOnTextBlock.fromJson(Map<String, dynamic> json) {
    return ClickOnTextBlock(
      documentId: json['documentId'] as String,
      blockId: json['blockId'] as String,
      segmentIndex: json['segmentIndex'] as int,
      offset: json['offset'] as int,
    );
  }
}
