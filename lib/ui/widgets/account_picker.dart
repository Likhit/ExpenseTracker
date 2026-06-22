import 'package:flutter/material.dart';

import '../../models/account.dart';

/// Bottom sheet for picking an asset/liability/equity account. Filters out the
/// built-in Expense and Income accounts and any soft-deleted entries; groups
/// the remainder by the root segment of their `::` path so a user with
/// `Chase::Checking` and `Chase::Savings` sees them together.
///
/// Returns the chosen [Account] via [Navigator.pop], or null if dismissed.
Future<Account?> pickAccount(BuildContext context, {
  required List<Account> accounts,
  Account? exclude,
  String title = 'Pick account',
}) {
  final pool = [
    for (final a in accounts)
      if (!a.deleted &&
          a.id != Account.expenseId &&
          a.id != Account.incomeId &&
          a.id != exclude?.id)
        a,
  ];

  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    builder: (_) => _AccountPickerSheet(pool: pool, title: title),
  );
}

class _AccountPickerSheet extends StatelessWidget {
  final List<Account> pool;
  final String title;

  const _AccountPickerSheet({required this.pool, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pool.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'No accounts yet. Create one from the Accounts screen first.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final grouped = <String, List<Account>>{};
    for (final a in pool) {
      grouped.putIfAbsent(a.root, () => []).add(a);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.path.compareTo(b.path));
    }
    final roots = grouped.keys.toList()..sort();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child:
                Text(title, style: theme.textTheme.titleLarge),
          ),
          for (final root in roots) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(root,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
            ),
            for (final a in grouped[root]!)
              ListTile(
                title: Text(a.displayName),
                subtitle: a.depth > 1 ? Text(a.path) : null,
                onTap: () => Navigator.of(context).pop(a),
              ),
          ],
        ],
      ),
    );
  }
}
