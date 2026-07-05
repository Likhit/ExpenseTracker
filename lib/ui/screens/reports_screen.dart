import 'package:flutter/material.dart';

import '../widgets/coming_soon.dart';

/// Reports hub (UX-spec "Reports"): a set of cards, each opening a drilldown.
/// The individual reports land in Phases 3.2–3.5; until each ships, its card
/// routes to a placeholder so the hub's navigation is complete and testable
/// now. Replace the placeholder target as each report screen lands.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  static const _reports = <_ReportEntry>[
    _ReportEntry(
      title: 'Spending by category',
      subtitle: 'Where your money goes, drillable by category depth',
      icon: Icons.pie_chart_outline,
    ),
    _ReportEntry(
      title: 'Income vs expense',
      subtitle: 'Cash in and out per period',
      icon: Icons.bar_chart_outlined,
    ),
    _ReportEntry(
      title: 'Net worth trend',
      subtitle: 'Asset and liability balances over time',
      icon: Icons.show_chart_outlined,
    ),
    _ReportEntry(
      title: 'Account balances',
      subtitle: 'Every account, grouped and multi-currency',
      icon: Icons.account_balance_outlined,
    ),
    _ReportEntry(
      title: 'Budgets',
      subtitle: 'Per-category budget vs actual',
      icon: Icons.savings_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final report in _reports)
            _ReportCard(
              entry: report,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComingSoon(title: report.title),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportEntry {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ReportEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _ReportCard extends StatelessWidget {
  final _ReportEntry entry;
  final VoidCallback onTap;

  const _ReportCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Icon(entry.icon),
        ),
        title: Text(entry.title),
        subtitle: Text(entry.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
