// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
class TextFormatEntity {
  final bool isBold;
  final bool isItalic;
  final bool isStroke;
  final bool isUnderline;

  const TextFormatEntity({
    this.isBold = false,
    this.isItalic = false,
    this.isStroke = false,
    this.isUnderline = false,
  });

  static const empty = TextFormatEntity();
}
