// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
abstract class BlockEntity {
  final String? parentId;
  final String id;
  final List<BlockEntity> children;

  const BlockEntity({
    required this.id,
    this.parentId,
    this.children = const [],
  });

  void dispose() {
    for (var c in children) {
      c.dispose();
    }
  }
}
