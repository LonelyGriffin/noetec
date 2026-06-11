// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:noetec/app/configure_di.dart';
import 'package:noetec/app/router.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:noetec/view/screens/main_app_loading_screen/main_app_loading_screen.dart';

class BootstrapWidget extends StatefulWidget {
  const BootstrapWidget({super.key});

  @override
  State<BootstrapWidget> createState() => _BootstrapWidgetState();
}

class _BootstrapWidgetState extends State<BootstrapWidget> {
  bool _isInitialized = false;
  GoRouter? _router;

  static const _appTitle = 'Noetec';
  static final _appTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    useMaterial3: true,
  );

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await configureDI();
    if (mounted) {
      setState(() {
        _router = createRouter(GetIt.I<VaultSystem>().currentVault);
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _router == null) {
      return MaterialApp(
        title: _appTitle,
        theme: _appTheme,
        home: const MainAppLoadingScreen(),
      );
    }

    return MaterialApp.router(
      title: _appTitle,
      theme: _appTheme,
      routerConfig: _router,
    );
  }
}
