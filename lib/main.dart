// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/main_app_widget.dart';
import 'package:noetec/systems/vault/vault_system.dart';

void main() async {
  final getIt = GetIt.instance;
  // Initializes platform channels required by DI-configured services.
  WidgetsFlutterBinding.ensureInitialized();

  await configureDI();
  await getIt<VaultSystem>().init();

  runApp(const MainApp());
}
