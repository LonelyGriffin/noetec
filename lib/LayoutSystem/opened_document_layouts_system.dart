import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';

class OpenedDocumentLayoutsSystem {
  final _viewportWidth = ValueNotifier<double>(0.0);

  late final ValueListenable<double> debouncedViewportWidth = _viewportWidth
      .debounce(Duration(milliseconds: 100));

  void setViewportWidth(double width) {
    _viewportWidth.value = width;
  }
}
