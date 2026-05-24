import 'package:flutter/material.dart';
import 'package:noetec/UserInputSystem/user_raw_text_input_service.dart';
import 'package:watch_it/watch_it.dart';

class DocumentEditorView extends WatchingWidget {
  const DocumentEditorView({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    // Используем Focus.of(context) для получения состояния фокуса
    // Это автоматически реактивно - виджет перестроится при изменении фокуса
    final onFocus = Focus.of(context).hasFocus;
    final testEditingText = watchValue(
      (UserRawTextInputService state) => state.getInputValue(id)!,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            border: Border.all(color: onFocus ? Colors.blue : Colors.red),
          ),
          child: Column(
            children: [
              Text(onFocus ? "Document is focused" : "Document is not focused"),
              Text(testEditingText.text),
            ],
          ),
        );
      },
    );
  }
}
