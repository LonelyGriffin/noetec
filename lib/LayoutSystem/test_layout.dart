import 'package:flutter/widgets.dart';
import 'package:noetec/LayoutSystem/opened_document_layouts_system.dart';
import 'package:watch_it/watch_it.dart';

class TestLayout extends WatchingWidget {
  const TestLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final width = watchValue(
      (OpenedDocumentLayoutsSystem state) => state.debouncedViewportWidth,
    );
    return Column(children: [Expanded(child: Text('Viewport Width: $width'))]);
  }
}
