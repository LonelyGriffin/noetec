// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const double _breakpoint = 720;

  static const _navItems = [
    _NavItem(path: '/welcome', label: 'Home', icon: Icons.home_outlined),
    _NavItem(path: '/editor', label: 'Editor', icon: Icons.edit_outlined),
    _NavItem(
      path: '/settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final activeIndex = _navItems.indexWhere(
      (item) => location.startsWith(item.path),
    );
    final isDesktop = MediaQuery.sizeOf(context).width >= _breakpoint;

    if (isDesktop) {
      return _DesktopShell(
        selectedIndex: activeIndex >= 0 ? activeIndex : 0,
        items: _navItems,
        child: child,
      );
    }

    return _MobileShell(
      selectedIndex: activeIndex >= 0 ? activeIndex : 0,
      items: _navItems,
      child: child,
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.selectedIndex,
    required this.items,
    required this.child,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => context.go(items[index].path),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.selectedIndex,
    required this.items,
    required this.child,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(items[index].path),
        destinations: [
          for (final item in items)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.path, required this.label, required this.icon});

  final String path;
  final String label;
  final IconData icon;
}
