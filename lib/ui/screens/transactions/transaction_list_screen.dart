import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/transaction.dart';
import '../../../models/account.dart';
import '../../../providers/storage_providers.dart';
import 'transaction_form_screen.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState
    extends ConsumerState<TransactionListScreen> {
  TransactionType? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          PopupMenuButton<TransactionType?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter by type',
            onSelected: (v) => setState(() => _typeFilter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              const PopupMenuItem(
                  value: TransactionType.expense, child: Text('Expenses')),
              const PopupMenuItem(
                  value: TransactionType.income, child: Text('Income')),
              const PopupMenuItem(
                  value: TransactionType.transfer, child: Text('Transfers')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (transactions) {
          final accounts =
              accountsAsync.value ?? <Account>[];
          var filtered = List<Transaction>.of(transactions);
          if (_typeFilter != null) {
            filtered = filtered
                .where((t) => t.type == _typeFilter)
                .toList();
          }
          // Sort by date descending
          filtered.sort((a, b) => b.date.compareTo(a.date));

          if (filtered.isEmpty) {
            return const Center(
              child: Text('No transactions yet. Tap + to add one.'),
            );
          }

          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final tx = filtered[index];
              return _TransactionTile(
                transaction: tx,
                accounts: accounts,
                onDelete: () =>
                    ref.read(transactionsProvider.notifier).remove(tx),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.red),
              title: const Text('Expense'),
              onTap: () {
                Navigator.pop(context);
                _openForm(TransactionType.expense);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward, color: Colors.green),
              title: const Text('Income'),
              onTap: () {
                Navigator.pop(context);
                _openForm(TransactionType.income);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.blue),
              title: const Text('Transfer'),
              onTap: () {
                Navigator.pop(context);
                _openForm(TransactionType.transfer);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(TransactionType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(type: type),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final List<Account> accounts;
  final VoidCallback onDelete;

  const _TransactionTile({
    required this.transaction,
    required this.accounts,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();
    final primaryLeg = transaction.legs.first;
    final categoryPath = transaction.legs
        .map((l) => l.categoryPath)
        .where((p) => p != null)
        .firstOrNull;

    final accountName = accounts
            .where((a) => a.id == primaryLeg.accountId)
            .firstOrNull
            ?.path ??
        'Unknown';

    final icon = _iconForType(transaction.type);
    final color = _colorForType(transaction.type);

    // For display: show the absolute amount of the first leg
    final displayAmount = primaryLeg.amount.startsWith('-')
        ? primaryLeg.amount.substring(1)
        : primaryLeg.amount;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        transaction.description.isEmpty
            ? (categoryPath ?? transaction.type.name)
            : transaction.description,
      ),
      subtitle: Text(
        [
          dateFormat.format(transaction.date),
          ?categoryPath,
          accountName,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_signForType(transaction.type)}$displayAmount ${primaryLeg.currencyCode}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForType(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return Icons.arrow_upward;
      case TransactionType.income:
        return Icons.arrow_downward;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }

  Color _colorForType(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return Colors.red;
      case TransactionType.income:
        return Colors.green;
      case TransactionType.transfer:
        return Colors.blue;
    }
  }

  String _signForType(TransactionType type) {
    switch (type) {
      case TransactionType.expense:
        return '-';
      case TransactionType.income:
        return '+';
      case TransactionType.transfer:
        return '';
    }
  }
}
