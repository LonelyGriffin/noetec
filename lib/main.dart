// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentView/document_editor_widget.dart';
import 'package:noetec/DocumentView/mobile_action_toolbar.dart';

import 'configure_di.dart';

void main() {
  configureDI();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final FocusNode _editorFocusNode;

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: TextField(
            decoration: InputDecoration(
              hintText: 'Search...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: DocumentEditorWidget(
                documentId: 'doc1',
                focusNode: _editorFocusNode,
              ),
            ),
            MobileActionToolbar(
              documentId: 'doc1',
              focusNode: _editorFocusNode,
            ),
          ],
        ),
      ),
    );
  }
}
