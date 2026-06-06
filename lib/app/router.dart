// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:noetec/app/app_shell.dart';
import 'package:noetec/systems/vault/vault_system.dart';
import 'package:noetec/view/screens/editor_screen/editor_screen.dart';
import 'package:noetec/view/screens/settings_screen/settings_screen.dart';
import 'package:noetec/view/screens/welcome_screen/welcome_screen.dart';

GoRouter createRouter() => GoRouter(
  initialLocation: '/welcome',
  redirect: (context, state) {
    final vault = GetIt.I<VaultSystem>().currentVault.value;
    final onWelcome = state.uri.path == '/welcome';

    if (vault == null && !onWelcome) return '/welcome';
    if (vault != null && onWelcome) return '/editor';
    return null;
  },
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/editor',
          builder: (context, state) => const EditorScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);
