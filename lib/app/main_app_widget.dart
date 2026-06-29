// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:noetec/app/router.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/persistence_system/persistence_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  late final _router = createRouter(GetIt.I<VaultSystem>().currentVault);

  static const _appTitle = 'Noetec';
  static final _appTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    useMaterial3: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await GetIt.I<PersistenceSystem>().saveAll();
      await GetIt.I<PageSystem>().saveSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: _appTitle,
      theme: _appTheme,
      routerConfig: _router,
    );
  }
}
