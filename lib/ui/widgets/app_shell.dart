import 'package:flutter/material.dart';

import '../screens/accounts_screen.dart';
import '../screens/home_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transactions_screen.dart';

/// Width at or above which the desktop/tablet [NavigationRail] takes over
/// from the mobile bottom [NavigationBar].
const double appShellRailBreakpoint = 600;

/// Top-level navigation shell. Adapts between a bottom [NavigationBar] on
/// narrow widths and a side [NavigationRail] on wider ones (Linux desktop,
/// foldables, large tablets). Each destination is rendered into the same body
/// region — Phase 2.1 only ships placeholder destinations; their real
/// contents land in 2.2 onwards.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      builder: HomeScreen.new,
    ),
    _Destination(
      label: 'Transactions',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      builder: TransactionsScreen.new,
    ),
    _Destination(
      label: 'Accounts',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      builder: AccountsScreen.new,
    ),
    _Destination(
      label: 'Reports',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      builder: ReportsScreen.new,
    ),
    _Destination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      builder: SettingsScreen.new,
    ),
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= appShellRailBreakpoint;
      final body = _destinations[_index].builder();
      return wide ? _wideLayout(body) : _narrowLayout(body);
    });
  }

  Widget _narrowLayout(Widget body) {
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final dest in _destinations)
            NavigationDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.selectedIcon),
              label: dest.label,
            ),
        ],
      ),
    );
  }

  Widget _wideLayout(Widget body) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final dest in _destinations)
                  NavigationRailDestination(
                    icon: Icon(dest.icon),
                    selectedIcon: Icon(dest.selectedIcon),
                    label: Text(dest.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;

  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
}
