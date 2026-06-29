import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/page_edit_action.dart';
import 'package:noetec/systems/page_system/page_action_dispatcher.dart';

void main() {
  group('PageActionDispatcher —', () {
    test('dispatch emits action to listeners', () {
      final dispatcher = PageActionDispatcher();
      final received = <PageEditAction>[];

      dispatcher.addListener((action) => received.add(action));
      dispatcher.dispatch(
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );

      expect(received, hasLength(1));
      expect(received.first, isA<InsertTextAction>());
    });

    test('removeListener stops notifications', () {
      final dispatcher = PageActionDispatcher();
      var count = 0;
      void listener(PageEditAction _) => count++;

      dispatcher.addListener(listener);
      dispatcher.dispatch(
        const InsertTextAction(blockId: 'b1', flatOffset: 0, text: 'a'),
      );
      dispatcher.removeListener(listener);
      dispatcher.dispatch(
        const InsertTextAction(blockId: 'b1', flatOffset: 1, text: 'b'),
      );

      expect(count, 1);
    });
  });
}
