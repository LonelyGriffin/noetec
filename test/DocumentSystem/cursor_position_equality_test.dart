// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/DocumentSystem/selection_state.dart';

void main() {
  // ---------------------------------------------------------------------------
  // CursorPositionInTextBlock equality
  // ---------------------------------------------------------------------------
  group('CursorPositionInTextBlock equality', () {
    test('equal positions are equal', () {
      const a = CursorPositionInTextBlock(blockId: 'b1', segmentIndex: 1, offset: 3);
      const b = CursorPositionInTextBlock(blockId: 'b1', segmentIndex: 1, offset: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different positions are not equal', () {
      const a = CursorPositionInTextBlock(blockId: 'b1', segmentIndex: 1, offset: 3);
      const b = CursorPositionInTextBlock(blockId: 'b1', segmentIndex: 1, offset: 4);
      expect(a, isNot(b));
    });
  });
}
