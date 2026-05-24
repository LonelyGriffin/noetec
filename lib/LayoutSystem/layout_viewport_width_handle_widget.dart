import 'package:flutter/widgets.dart';
import 'package:noetec/LayoutSystem/opened_document_layouts_system.dart';
import 'package:watch_it/watch_it.dart';

class LayoutViewportWidthHandleWidget extends StatelessWidget {
  const LayoutViewportWidthHandleWidget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        di<OpenedDocumentLayoutsSystem>().setViewportWidth(
          constraints.maxWidth,
        );
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: child,
        );
      },
    );
  }
}
