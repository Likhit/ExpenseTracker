import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/transaction.dart';
import '../../../models/account.dart';
import '../../../models/category.dart';
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
  String? _accountIdFilter;
  String? _categoryPathFilter;
  DateTimeRange? _dateRange;

  bool get _hasFilters =>
      _typeFilter != null ||
      _accountIdFilter != null ||
      _categoryPathFilter != null ||
      _dateRange != null;

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _hasFilters,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filters',
            onPressed: () => _showFilterSheet(context),
          ),
          if (_hasFilters)
            IconButton(
              icon: const Icon(Icons.filter_list_off),
              tooltip: 'Clear filters',
              onPressed: () => setState(() {
                _typeFilter = null;
                _accountIdFilter = null;
                _categoryPathFilter = null;
                _dateRange = null;
              }),
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
          final accounts = accountsAsync.value ?? <Account>[];
          var filtered = _applyFilters(List<Transaction>.of(transactions));
          filtered.sort((a, b) => b.date.compareTo(a.date));

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _hasFilters
                    ? 'No transactions match your filters.'
                    : 'No transactions yet. Tap + to add one.',
              ),
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

  List<Transaction> _applyFilters(List<Transaction> transactions) {
    var result = transactions;

    if (_typeFilter != null) {
      result = result.where((t) => t.type == _typeFilter).toList();
    }

    if (_accountIdFilter != null) {
      result = result
          .where((t) => t.legs.any((l) => l.accountId == _accountIdFilter))
          .toList();
    }

    if (_categoryPathFilter != null) {
      result = result
          .where((t) => t.legs.any((l) =>
              l.categoryPath != null &&
              l.categoryPath!.startsWith(_categoryPathFilter!)))
          .toList();
    }

    if (_dateRange != null) {
      result = result.where((t) {
        final d = t.date;
        return !d.isBefore(_dateRange!.start) && !d.isAfter(_dateRange!.end);
      }).toList();
    }

    return result;
  }

  void _showFilterSheet(BuildContext context) {
    final accounts = ref.read(accountsProvider).value ?? <Account>[];
    final categories = ref.read(categoriesProvider).value ?? <Category>[];
    final rootCategories = categories.where((c) => c.depth == 1).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filters',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),

              // Type filter
              DropdownButtonFormField<TransactionType?>(
                initialValue: _typeFilter,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...TransactionType.values.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                            t.name[0].toUpperCase() + t.name.substring(1)),
                      )),
                ],
                onChanged: (v) => setState(() => _typeFilter = v),
              ),
              const SizedBox(height: 12),

              // Account filter
              DropdownButtonFormField<String?>(
                initialValue: _accountIdFilter,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...accounts.map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.path),
                      )),
                ],
                onChanged: (v) => setState(() => _accountIdFilter = v),
              ),
              const SizedBox(height: 12),

              // Category filter
              DropdownButtonFormField<String?>(
                initialValue: _categoryPathFilter,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...rootCategories.map((c) => DropdownMenuItem(
                        value: c.path,
                        child: Text(c.path),
                      )),
                ],
                onChanged: (v) => setState(() => _categoryPathFilter = v),
              ),
              const SizedBox(height: 12),

              // Date range
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_dateRange != null
                    ? '${DateFormat.yMMMd().format(_dateRange!.start)} — ${DateFormat.yMMMd().format(_dateRange!.end)}'
                    : 'All dates'),
                leading: const Icon(Icons.date_range),
                trailing: _dateRange != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _dateRange = null),
                      )
                    : null,
                onTap: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDateRange: _dateRange,
                  );
                  if (range != null) {
                    setState(() => _dateRange = range);
                  }
                },
              ),
              const SizedBox(height: 16),

              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
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
