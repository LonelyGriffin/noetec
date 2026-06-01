// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:noetec/DocumentView/document_editor_widget.dart';

import 'configure_di.dart';

void main() {
  configureDI();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
        body: DocumentEditorWidget(documentId: 'doc1'),
      ),
    );
  }
}
