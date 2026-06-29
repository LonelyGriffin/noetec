// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/page/block/text/text_format.dart';

@immutable
class TextSegment {
  final String text;

  const TextSegment({required this.text});

  TextSegment cloneWithText(String newText) => TextSegment(text: newText);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TextSegment && other.text == text);

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TextSegment(text: "$text")';
}

@immutable
class FormattedSegment extends TextSegment {
  final TextFormat format;

  const FormattedSegment({required super.text, required this.format});

  @override
  FormattedSegment cloneWithText(String newText) =>
      FormattedSegment(text: newText, format: format);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FormattedSegment &&
          other.text == text &&
          other.format == format);

  @override
  int get hashCode => text.hashCode ^ format.hashCode;

  @override
  String toString() => 'FormattedSegment(text: "$text", format: $format)';
}

@immutable
class LinkSegment extends TextSegment {
  final String url;

  const LinkSegment({required super.text, required this.url});

  @override
  LinkSegment cloneWithText(String newText) =>
      LinkSegment(text: newText, url: url);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkSegment && other.text == text && other.url == url);

  @override
  int get hashCode => text.hashCode ^ url.hashCode;

  @override
  String toString() => 'LinkSegment(text: "$text", url: "$url")';
}
