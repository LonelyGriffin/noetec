// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';
import 'package:noetec/entity/document/block/block.dart';
import 'package:noetec/entity/document/block/text/text_attribute.dart';

@immutable
class TextBlockEntity extends BlockEntity {
  final String text;
  final List<TextAttributeEntity> attributes;

  const TextBlockEntity._({
    required super.id,
    required super.parentId,
    required this.text,
    required this.attributes,
  });

  factory TextBlockEntity({
    required String id,
    required String parentId,
    required String text,
  }) {
    return TextBlockEntity._(
      id: id,
      parentId: parentId,
      text: text,
      attributes: [FormatedTextAttributeEntity(from: 0, to: text.length)],
    );
  }

  static TextBlockEntity fromBuilder({
    required TextBlockEntityBuilder builder,
  }) {
    return TextBlockEntity._(
      id: builder.id,
      parentId: builder.parentId!,
      text: builder.text,
      attributes: builder.attributes,
    );
  }
}

class TextBlockEntityBuilder {
  final String _id;
  final String? _parentId;
  final String _text;
  List<TextAttributeEntity> _attributes;

  TextBlockEntityBuilder({
    required String text,
    required String id,
    required String? parentId,
    List<FormatedTextAttributeEntity>? attributes,
  }) : _id = id,
       _parentId = parentId,
       _text = text,
       _attributes =
           attributes ??
           [FormatedTextAttributeEntity(from: 0, to: text.length)];

  String get id => _id;
  String get text => _text;
  String? get parentId => _parentId;
  List<TextAttributeEntity> get attributes {
    return List.unmodifiable(_attributes);
  }

  TextBlockEntity build() {
    return TextBlockEntity.fromBuilder(builder: this);
  }

  TextBlockEntityBuilder setAttribute({required TextAttributeEntity attr}) {
    List<TextAttributeEntity> result = [];
    bool inserted = false;

    void addWithMerge(
      List<TextAttributeEntity> list,
      TextAttributeEntity newAttr,
    ) {
      if (list.isNotEmpty && list.last.equalByAttrs(newAttr)) {
        list[list.length - 1] = list.last.copyWithRange(
          from: list.last.from,
          to: newAttr.to,
        );
      } else {
        list.add(newAttr);
      }
    }

    for (var existing in _attributes) {
      if (existing.to <= attr.from) {
        addWithMerge(result, existing);
        continue;
      }

      if (!inserted && existing.from >= attr.to) {
        addWithMerge(result, attr);
        inserted = true;
      }

      if (existing.from >= attr.to) {
        addWithMerge(result, existing);
        continue;
      }

      // Overlap
      if (existing.from < attr.from) {
        addWithMerge(
          result,
          existing.copyWithRange(from: existing.from, to: attr.from),
        );
      }

      if (!inserted) {
        addWithMerge(result, attr);
        inserted = true;
      }

      if (existing.to > attr.to) {
        addWithMerge(
          result,
          existing.copyWithRange(from: attr.to, to: existing.to),
        );
      }
    }

    if (!inserted) {
      addWithMerge(result, attr);
    }

    _attributes = result;
    return this;
  }
}
