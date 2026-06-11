// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';

@immutable
abstract class TextAttributeEntity {
  final int from;
  final int to;

  const TextAttributeEntity({required this.from, required this.to});

  bool equalByAttrs(TextAttributeEntity other);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextAttributeEntity &&
        from == other.from &&
        to == other.to &&
        equalByAttrs(other);
  }

  @override
  int get hashCode => from.hashCode ^ to.hashCode;

  TextAttributeEntity copyWithRange({required int from, required int to});
}

@immutable
class FormatedTextAttributeEntity extends TextAttributeEntity {
  final TextFormatEntity format;

  const FormatedTextAttributeEntity({
    required super.from,
    required super.to,
    this.format = TextFormatEntity.empty,
  });

  @override
  // ignore: hash_and_equals - because TextAttributeEntity operator ==(Object other) is common
  int get hashCode => super.hashCode ^ format.hashCode;

  @override
  FormatedTextAttributeEntity copyWithRange({
    required int from,
    required int to,
  }) {
    return FormatedTextAttributeEntity(from: from, to: to, format: format);
  }

  @override
  bool equalByAttrs(TextAttributeEntity other) =>
      other is FormatedTextAttributeEntity && format == other.format;
}

@immutable
class LinkTextAttributeEntity extends TextAttributeEntity {
  final String url;

  const LinkTextAttributeEntity({
    required super.from,
    required super.to,
    required this.url,
  });

  @override
  // ignore: hash_and_equals - because TextAttributeEntity operator ==(Object other) is common
  int get hashCode => super.hashCode ^ url.hashCode;

  @override
  LinkTextAttributeEntity copyWithRange({required int from, required int to}) {
    return LinkTextAttributeEntity(from: from, to: to, url: url);
  }

  @override
  bool equalByAttrs(TextAttributeEntity other) =>
      other is LinkTextAttributeEntity && url == other.url;
}
