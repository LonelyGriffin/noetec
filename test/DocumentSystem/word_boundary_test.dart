// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_it/listen_it.dart';
import 'package:noetec/DocumentSystem/document_block.dart';

/// Convenience helper: creates a plain [TextBlock] with a single segment.
TextBlock _block(String text, {String id = 'b1'}) {
  return TextBlock(
    id: id,
    documentId: 'doc',
    parent: ValueNotifier(null),
    segments: ListNotifier(data: [TextSegment(text: text)]),
  );
}

/// Convenience helper: creates a [TextBlock] with the given segments.
TextBlock _multiSegBlock(List<TextSegment> segs, {String id = 'b1'}) {
  return TextBlock(
    id: id,
    documentId: 'doc',
    parent: ValueNotifier(null),
    segments: ListNotifier(data: segs),
  );
}

void main() {
  group('TextBlock.wordBoundaryAt', () {
    test('word in the middle of text', () {
      final b = _block('Hello World');
      // offset 2 is inside "Hello"
      expect(b.wordBoundaryAt(2), (0, 5));
    });

    test('word at the start', () {
      final b = _block('Hello World');
      expect(b.wordBoundaryAt(0), (0, 5));
    });

    test('word at the end', () {
      final b = _block('Hello World');
      // offset 8 is inside "World"
      expect(b.wordBoundaryAt(8), (6, 11));
    });

    test('offset at end of last word', () {
      final b = _block('Hello World');
      // offset 11 == text.length, should select last word
      expect(b.wordBoundaryAt(11), (6, 11));
    });

    test('on a space character', () {
      final b = _block('Hello World');
      // offset 5 is the space between "Hello" and "World"
      expect(b.wordBoundaryAt(5), (5, 6));
    });

    test('single character word', () {
      final b = _block('a');
      expect(b.wordBoundaryAt(0), (0, 1));
    });

    test('empty block', () {
      final b = _block('');
      expect(b.wordBoundaryAt(0), (0, 0));
    });

    test('punctuation after word', () {
      // "Hello, World!" -- offset 5 is comma
      final b = _block('Hello, World!');
      expect(b.wordBoundaryAt(5), (5, 6), reason: 'comma is non-word');
    });

    test('word before punctuation', () {
      final b = _block('Hello, World!');
      // offset 4 is 'o' in "Hello"
      expect(b.wordBoundaryAt(4), (0, 5));
    });

    test('word after punctuation', () {
      final b = _block('Hello, World!');
      // offset 7 is 'W' in "World"
      expect(b.wordBoundaryAt(7), (7, 12));
    });

    test('underscore is part of word', () {
      final b = _block('hello_world test');
      expect(b.wordBoundaryAt(3), (0, 11));
    });

    test('digits are part of word', () {
      final b = _block('abc123 xyz');
      expect(b.wordBoundaryAt(4), (0, 6));
    });

    test('multi-segment: word boundary crosses segments', () {
      // "Hello " + "bold" + " world" = "Hello bold world"
      final b = _multiSegBlock([
        const TextSegment(text: 'Hello '),
        const FormattedSegment(text: 'bold', format: TextFormat.bold),
        const TextSegment(text: ' world'),
      ]);
      // offset 7 is 'o' in "bold" (flat: "Hello bold world")
      expect(b.wordBoundaryAt(7), (6, 10));
    });

    test('multi-segment: word at segment boundary', () {
      // "ab" + "cd" = "abcd"
      final b = _multiSegBlock([
        const TextSegment(text: 'ab'),
        const TextSegment(text: 'cd'),
      ]);
      // offset 1 is 'b' -- word spans both segments
      expect(b.wordBoundaryAt(1), (0, 4));
    });

    test('offset clamped when negative', () {
      final b = _block('Hello');
      expect(b.wordBoundaryAt(-5), (0, 5));
    });

    test('offset clamped when beyond text length', () {
      final b = _block('Hello');
      expect(b.wordBoundaryAt(100), (0, 5));
    });
  });
}
