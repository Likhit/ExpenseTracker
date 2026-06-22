import 'package:flutter/material.dart';

import '../../models/transaction.dart';

/// Bottom sheet that asks the user which kind of transaction they're about to
/// add. Three big tiles (Expense, Income, Transfer) — matches the UX-spec FAB
/// chooser. Returns the picked [TransactionType] (transfer uses
/// [TransactionType.transfer]) via [Navigator.pop].
Future<TransactionType?> pickTransactionType(BuildContext context) {
  return showModalBottomSheet<TransactionType>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeTile(
            icon: Icons.north_east,
            iconColor: Colors.red,
            title: 'Expense',
            subtitle: 'Money going out',
            type: TransactionType.expense,
          ),
          _TypeTile(
            icon: Icons.south_west,
            iconColor: Colors.green,
            title: 'Income',
            subtitle: 'Money coming in',
            type: TransactionType.income,
          ),
          _TypeTile(
            icon: Icons.swap_horiz,
            iconColor: Colors.blueGrey,
            title: 'Transfer',
            subtitle: 'Between your accounts',
            type: TransactionType.transfer,
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _TypeTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final TransactionType type;

  const _TypeTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.15),
        foregroundColor: iconColor,
        child: Icon(icon),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).pop(type),
    );
  }
}
