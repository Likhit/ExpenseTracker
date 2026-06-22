import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/path_helper.dart';
import '../../models/transaction.dart';
import '../../providers/balances_provider.dart';
import '../../providers/ledger_provider.dart';
import '../widgets/transaction_filter_bar.dart';
import '../widgets/transaction_row.dart';
import '../widgets/transaction_type_sheet.dart';
import 'expense_income_entry_screen.dart';
import 'transfer_entry_screen.dart';

/// Transactions destination. Filter bar across the top, day-grouped reverse-
/// chrono list below, FAB → type chooser → entry flow. Tap a row to edit;
/// popup menu soft-deletes or restores.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionsFilter _filter = const TransactionsFilter();
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final accountsById = {for (final a in accounts) a.id: a};
    final currenciesByCode = ref.watch(currenciesByCodeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_showDeleted
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            tooltip: _showDeleted ? 'Hide deleted' : 'Show deleted',
            onPressed: () => setState(() => _showDeleted = !_showDeleted),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: TransactionsFilterBar(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (all) {
          final visible = _filterAndSort(all);
          if (visible.isEmpty) {
            return _EmptyState(hasFilters: !_filter.isEmpty);
          }
          return _TransactionsList(
            transactions: visible,
            accountsById: accountsById,
            currenciesByCode: currenciesByCode,
            onEdit: (tx) => _editTransaction(context, tx),
            onDelete: (tx) => _delete(context, tx),
            onRestore: (tx) => _restore(tx),
          );
        },
      ),
    );
  }

  List<Transaction> _filterAndSort(List<Transaction> all) {
    final out = <Transaction>[];
    for (final tx in all) {
      if (!_showDeleted && tx.deleted) continue;
      if (_filter.types != null && !_filter.types!.contains(tx.type)) continue;
      if (_filter.dateRange != null) {
        final start = _filter.dateRange!.start;
        final end = _filter.dateRange!.end
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
        if (tx.date.isBefore(start) || tx.date.isAfter(end)) continue;
      }
      if (_filter.accounts != null) {
        final hit = tx.legs.any((l) => _filter.accounts!.contains(l.accountId));
        if (!hit) continue;
      }
      if (_filter.categories != null) {
        final hit = tx.legs.any((l) {
          final path = l.categoryPath;
          if (path == null) return false;
          return _filter.categories!.any(path.matches);
        });
        if (!hit) continue;
      }
      out.add(tx);
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> _addTransaction(BuildContext context) async {
    final type = await pickTransactionType(context);
    if (type == null || !context.mounted) return;
    final route = switch (type) {
      TransactionType.expense || TransactionType.income =>
        MaterialPageRoute<Transaction>(
          builder: (_) => ExpenseIncomeEntryScreen(type: type),
          fullscreenDialog: true,
        ),
      TransactionType.transfer => MaterialPageRoute<Transaction>(
          builder: (_) => const TransferEntryScreen(),
          fullscreenDialog: true,
        ),
    };
    await Navigator.of(context).push(route);
  }

  Future<void> _editTransaction(
      BuildContext context, Transaction tx) async {
    final route = tx.type == TransactionType.transfer
        ? MaterialPageRoute<Transaction>(
            builder: (_) => TransferEntryScreen(existing: tx),
            fullscreenDialog: true,
          )
        : MaterialPageRoute<Transaction>(
            builder: (_) =>
                ExpenseIncomeEntryScreen(type: tx.type, existing: tx),
            fullscreenDialog: true,
          );
    await Navigator.of(context).push(route);
  }

  Future<void> _delete(BuildContext context, Transaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
            'Soft-delete this transaction. You can restore it from "Show deleted" later.'),
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
    await ledger.delete(tx);
  }

  Future<void> _restore(Transaction tx) async {
    final ledger = await ref.read(ledgerProvider.future);
    await ledger.save(tx.copyWith(deleted: false, updatedAt: DateTime.now()));
  }
}

class _TransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final Map<dynamic, Account> accountsById;
  final Map<dynamic, dynamic> currenciesByCode;
  final ValueChanged<Transaction> onEdit;
  final ValueChanged<Transaction> onDelete;
  final ValueChanged<Transaction> onRestore;

  const _TransactionsList({
    required this.transactions,
    required this.accountsById,
    required this.currenciesByCode,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    // Build the (header, rows) sequence by walking newest-first and emitting a
    // header each time the day changes.
    final children = <Widget>[];
    String? currentDay;
    for (final tx in transactions) {
      final dayKey = _dayKey(tx.date);
      if (dayKey != currentDay) {
        currentDay = dayKey;
        children.add(_DayHeader(date: tx.date));
      }
      children.add(TransactionRow(
        transaction: tx,
        accountsById: accountsById.cast(),
        currenciesByCode: currenciesByCode.cast(),
        onTap: () => onEdit(tx),
        onEdit: () => onEdit(tx),
        onDelete: () => onDelete(tx),
        onRestore: () => onRestore(tx),
      ));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: children,
    );
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DayHeader extends StatelessWidget {
  final DateTime date;

  const _DayHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);
    final String label;
    if (day == today) {
      label = 'Today';
    } else if (day == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat.yMMMMEEEEd().format(date);
    }
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

class _EmptyState extends StatelessWidget {
  final bool hasFilters;

  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No transactions match the current filters.'
                  : 'No transactions yet.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Adjust the chips above or clear filters to see everything.'
                  : 'Tap "Add" to record your first one.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
