import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/systems/persistence_system/wal_action_serializer.dart';

void main() {
  group('WalActionSerializer —', () {
    const serializer = WalActionSerializer();

    test('InsertText roundtrip', () {
      const action = InsertTextAction(
        blockId: 'b1',
        flatOffset: 5,
        text: 'hello',
      );
      final json = serializer.toJson(action);
      final restored = serializer.fromJson(json);

      expect(restored, isA<InsertTextAction>());
      final restoredInsert = restored as InsertTextAction;
      expect(restoredInsert.blockId, 'b1');
      expect(restoredInsert.flatOffset, 5);
      expect(restoredInsert.text, 'hello');
    });

    test('PasteText roundtrip', () {
      const action = PasteTextAction(
        blockId: 'b1',
        clipboardContent: 'pasted text',
        flatOffset: 0,
      );
      final json = serializer.toJson(action);
      final restored = serializer.fromJson(json);

      expect(restored, isA<PasteTextAction>());
      final restoredPaste = restored as PasteTextAction;
      expect(restoredPaste.blockId, 'b1');
      expect(restoredPaste.clipboardContent, 'pasted text');
      expect(restoredPaste.flatOffset, 0);
    });

    test('fromJson throws FormatException for unknown type', () {
      expect(
        () => serializer.fromJson({'type': 'unknown_action', 'block_id': 'b1'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson includes type field', () {
      const action = InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'x');
      final json = serializer.toJson(action);
      expect(json['type'], 'insert_text');
    });
  });
}
