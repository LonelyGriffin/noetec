// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
class TextFormat {
  final int _flags;

  const TextFormat._(this._flags);

  int get flags => _flags;

  static const TextFormat none = TextFormat._(0);
  static const TextFormat bold = TextFormat._(1 << 0);
  static const TextFormat italic = TextFormat._(1 << 1);
  static const TextFormat strikethrough = TextFormat._(1 << 2);
  static const TextFormat underline = TextFormat._(1 << 3);

  factory TextFormat.fromFlags(int flags) => TextFormat._(flags);

  bool has(TextFormat flag) => (_flags & flag._flags) == flag._flags;

  TextFormat operator |(TextFormat other) =>
      TextFormat._(_flags | other._flags);

  TextFormat without(TextFormat other) => TextFormat._(_flags & ~other._flags);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TextFormat && other._flags == _flags);

  @override
  int get hashCode => _flags.hashCode;

  @override
  String toString() => 'TextFormat($_flags)';
}
