import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../providers/balances_provider.dart';
import '../../providers/ledger_provider.dart';
import '../format/money.dart';
import '../widgets/account_edit_dialog.dart';

/// Accounts list: a pinned "System accounts" section for the built-in
/// Expense/Income, followed by user-created accounts grouped by the root
/// segment of their `::` path. Each row shows per-currency balances.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: Icon(_showDeleted
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            tooltip: _showDeleted ? 'Hide deleted' : 'Show deleted',
            onPressed: () => setState(() => _showDeleted = !_showDeleted),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AccountEditDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New account'),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load accounts: $e')),
        data: (all) => _AccountsList(accounts: all, showDeleted: _showDeleted),
      ),
    );
  }
}

class _AccountsList extends ConsumerWidget {
  final List<Account> accounts;
  final bool showDeleted;

  const _AccountsList({required this.accounts, required this.showDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builtins = <Account>[];
    final user = <Account>[];
    for (final a in accounts) {
      if (a.deleted && !showDeleted) continue;
      if (a.id == Account.expenseId || a.id == Account.incomeId) {
        builtins.add(a);
      } else {
        user.add(a);
      }
    }
    // Built-ins in a fixed order: Expense first, Income second.
    builtins.sort((a, b) =>
        a.id == Account.expenseId ? -1 : (b.id == Account.expenseId ? 1 : 0));

    // Group user accounts by root segment, in alphabetical order; accounts
    // within a group sort by their full path.
    final grouped = <String, List<Account>>{};
    for (final a in user) {
      grouped.putIfAbsent(a.root, () => []).add(a);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.path.compareTo(b.path));
    }
    final roots = grouped.keys.toList()..sort();

    if (builtins.isEmpty && roots.isEmpty) {
      return const _EmptyAccounts();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (builtins.isNotEmpty) ...[
          const _SectionHeader(label: 'System accounts'),
          for (final a in builtins) _AccountTile(account: a, readOnly: true),
        ],
        for (final root in roots) ...[
          _SectionHeader(label: root),
          for (final a in grouped[root]!) _AccountTile(account: a),
        ],
      ],
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              'No accounts yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "New account" to create your first one.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  final Account account;
  final bool readOnly;

  const _AccountTile({required this.account, this.readOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balances = ref.watch(balancesProvider).value?[account.id];
    final currencies = ref.watch(currenciesByCodeProvider);

    final balanceWidgets = <Widget>[];
    if (balances != null) {
      for (final entry in balances.entries) {
        balanceWidgets.add(Text(
          formatMoney(entry.value, currencies[entry.key]),
          style: theme.textTheme.bodyMedium,
        ));
      }
    }

    final deleted = account.deleted;
    final titleStyle = deleted
        ? theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          )
        : theme.textTheme.bodyLarge;

    return ListTile(
      leading: Icon(_iconFor(account.type)),
      title: Text(account.displayName, style: titleStyle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_subtitleFor(account)),
          if (balanceWidgets.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...balanceWidgets,
          ],
        ],
      ),
      isThreeLine: balanceWidgets.isNotEmpty,
      trailing: readOnly
          ? null
          : PopupMenuButton<_AccountAction>(
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (_) => [
                if (!deleted)
                  const PopupMenuItem(
                    value: _AccountAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                    ),
                  ),
                if (!deleted)
                  const PopupMenuItem(
                    value: _AccountAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                if (deleted)
                  const PopupMenuItem(
                    value: _AccountAction.restore,
                    child: ListTile(
                      leading: Icon(Icons.restore),
                      title: Text('Restore'),
                    ),
                  ),
              ],
            ),
      onTap: readOnly || deleted
          ? null
          : () => AccountEditDialog.show(context, existing: account),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, _AccountAction action) async {
    switch (action) {
      case _AccountAction.edit:
        await AccountEditDialog.show(context, existing: account);
      case _AccountAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete account?'),
            content: Text(
                'Soft-delete "${account.path}". You can restore it from "Show deleted" later.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed != true) return;
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.delete(account);
      case _AccountAction.restore:
        // Restoring = re-saving a non-deleted version with a bumped updatedAt.
        // The repo appends a new line; latest-version-per-id reconstructs the
        // restored state on next read.
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.save(
            account.copyWith(deleted: false, updatedAt: DateTime.now()));
    }
  }
}

String _subtitleFor(Account a) {
  final parts = <String>[_typeLabel(a.type)];
  if (a.isVirtual) parts.add('virtual');
  if (a.depth > 1) parts.add(a.pathSegments.take(a.depth - 1).join('::'));
  return parts.join(' · ');
}

String _typeLabel(AccountType t) => switch (t) {
      AccountType.asset => 'Asset',
      AccountType.liability => 'Liability',
      AccountType.equity => 'Equity',
      AccountType.income => 'Income',
      AccountType.expense => 'Expense',
    };

IconData _iconFor(AccountType t) => switch (t) {
      AccountType.asset => Icons.account_balance_wallet_outlined,
      AccountType.liability => Icons.credit_card_outlined,
      AccountType.equity => Icons.savings_outlined,
      AccountType.income => Icons.south_west,
      AccountType.expense => Icons.north_east,
    };

enum _AccountAction { edit, delete, restore }
