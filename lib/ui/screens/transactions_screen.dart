import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/transaction.dart';
import '../widgets/transaction_type_sheet.dart';
import 'expense_income_entry_screen.dart';
import 'transfer_entry_screen.dart';

/// Transactions destination. Phase 2.5 wires the FAB → type chooser → entry
/// flow; Phase 2.6 replaces the placeholder body with the real reverse-chrono
/// list and filter bar.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      // Phase 2.6 replaces this body with the real list. Until then the FAB
      // flow is wired and testable on its own.
      body: Center(
        child: Text(
          'Tap "Add" to record a transaction.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
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
}
