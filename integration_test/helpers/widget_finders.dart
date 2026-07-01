import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/view/widgets/editor/text_block_render_widget.dart';

Finder findCreateVaultButton() =>
    find.widgetWithText(FilledButton, 'Create Vault');
Finder findOpenVaultButton() =>
    find.widgetWithText(OutlinedButton, 'Open Vault');
Finder findVaultNameField() => find.byType(TextField);
Finder findDialogCreateButton() => find.widgetWithText(FilledButton, 'Create');
Finder findDialogCancelButton() => find.widgetWithText(TextButton, 'Cancel');

// Settings panel
Finder findOpenAnotherVaultButton() =>
    find.widgetWithText(OutlinedButton, 'Open Another Vault');

// Tab bar
Finder findTabWithTitle(String title) => find.byKey(Key('tab-$title'));

Finder findTabCloseButton(String title) => find.descendant(
  of: findTabWithTitle(title),
  matching: find.byIcon(Icons.close),
);

Finder findTabUnsavedIndicator(String title) => find.descendant(
  of: findTabWithTitle(title),
  matching: find.byIcon(Icons.circle),
);

// Pages panel
Finder findPageInPanel(String name) => find.text(name);
Finder findNewPageButton() => find.byTooltip('New Page');
Finder findPageRenameField() => find.byType(TextField);

// Recent vaults
Finder findRecentVaultEntry(String name) => find.widgetWithText(ListTile, name);

// Rail panel buttons
Finder findPagesPanelButton() => find.byTooltip('Pages');
Finder findSettingsPanelButton() => find.byTooltip('Settings');

// Editor
Finder findEditorBlock() => find.byType(TextBlockRenderWidget).first;

Future<TestGesture> hoverOver(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
  return gesture;
}

Future<void> hoverAway(WidgetTester tester, TestGesture gesture) async {
  await gesture.moveTo(Offset.zero);
  await tester.pumpAndSettle();
  await gesture.removePointer();
}
