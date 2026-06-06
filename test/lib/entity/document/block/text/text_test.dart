// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/document/block/text/text.dart';
import 'package:noetec/entity/document/block/text/text_attribute.dart';
import 'package:noetec/entity/document/block/text/text_format.dart';

void main() {
  group('TextBlockEntityBuilder.setAttribute', () {
    const emptyFormat = TextFormatEntity.empty;
    const boldFormat = TextFormatEntity(isBold: true);
    const italicFormat = TextFormatEntity(isItalic: true);

    TextBlockEntityBuilder createBuilder({
      String text = '1234567890',
      List<FormatedTextAttributeEntity>? attributes,
    }) {
      return TextBlockEntityBuilder(
        text: text,
        id: 'test-id',
        parentId: 'parent-id',
        attributes:
            attributes ??
            [
              FormatedTextAttributeEntity(
                from: 0,
                to: text.length,
                format: emptyFormat,
              ),
            ],
      );
    }

    test('Splitting an existing attribute', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(
            from: 0,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 3,
          to: 7,
          format: boldFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 3, format: emptyFormat),
        const FormatedTextAttributeEntity(from: 3, to: 7, format: boldFormat),
        const FormatedTextAttributeEntity(from: 7, to: 10, format: emptyFormat),
      ]);
    });

    test('Merging with left neighbor (identical attributes)', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(from: 0, to: 5, format: boldFormat),
          const FormatedTextAttributeEntity(
            from: 5,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 3,
          to: 6,
          format: boldFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 6, format: boldFormat),
        const FormatedTextAttributeEntity(from: 6, to: 10, format: emptyFormat),
      ]);
    });

    test('Merging with right neighbor (identical attributes)', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(
            from: 0,
            to: 5,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 5,
            to: 10,
            format: boldFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 4,
          to: 8,
          format: boldFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 4, format: emptyFormat),
        const FormatedTextAttributeEntity(from: 4, to: 10, format: boldFormat),
      ]);
    });

    test('Replacing multiple segments', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(
            from: 0,
            to: 3,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 3,
            to: 6,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 6,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 2,
          to: 8,
          format: italicFormat,
        ),
      ); // Wait, I'm still seeing a typo in my copy-paste!

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 2, format: emptyFormat),
        const FormatedTextAttributeEntity(from: 2, to: 8, format: italicFormat),
        const FormatedTextAttributeEntity(from: 8, to: 10, format: emptyFormat),
      ]);
    });

    test('Insertion at the beginning (no merging)', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(from: 0, to: 5, format: boldFormat),
          const FormatedTextAttributeEntity(
            from: 5,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 0,
          to: 2,
          format: italicFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 2, format: italicFormat),
        const FormatedTextAttributeEntity(from: 2, to: 5, format: boldFormat),
        const FormatedTextAttributeEntity(from: 5, to: 10, format: emptyFormat),
      ]);
    });

    test('Insertion at the end (no merging)', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(
            from: 0,
            to: 5,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 5,
            to: 10,
            format: boldFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 8,
          to: 10,
          format: italicFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 5, format: emptyFormat),
        const FormatedTextAttributeEntity(from: 5, to: 8, format: boldFormat),
        const FormatedTextAttributeEntity(
          from: 8,
          to: 10,
          format: italicFormat,
        ),
      ]);
    });

    test('Inserting a duplicate attribute', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(from: 0, to: 5, format: boldFormat),
          const FormatedTextAttributeEntity(
            from: 5,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 0,
          to: 5,
          format: boldFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(from: 0, to: 5, format: boldFormat),
        const FormatedTextAttributeEntity(from: 5, to: 10, format: emptyFormat),
      ]);
    });

    test('Expanding to cover the entire string', () {
      final builder = createBuilder(
        attributes: [
          const FormatedTextAttributeEntity(
            from: 0,
            to: 3,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 3,
            to: 6,
            format: emptyFormat,
          ),
          const FormatedTextAttributeEntity(
            from: 6,
            to: 10,
            format: emptyFormat,
          ),
        ],
      );

      builder.setAttribute(
        attr: const FormatedTextAttributeEntity(
          from: 0,
          to: 10,
          format: italicFormat,
        ),
      );

      final result = builder.build().attributes;
      expect(result, [
        const FormatedTextAttributeEntity(
          from: 0,
          to: 10,
          format: italicFormat,
        ),
      ]);
    });
  });
}
