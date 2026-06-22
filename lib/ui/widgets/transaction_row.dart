import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/currency.dart';
import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import '../format/money.dart';

/// One row in the transactions list. Renders the type icon, a one-line
/// description (or category fallback), the user-side account path, and the
/// signed amount in its currency. Expense red, income green; transfers
/// render in the neutral on-surface color.
class TransactionRow extends StatelessWidget {
  final Transaction transaction;
  final Map<AccountId, Account> accountsById;
  final Map<CurrencyCode, Currency> currenciesByCode;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRestore;

  const TransactionRow({
    required this.transaction,
    required this.accountsById,
    required this.currenciesByCode,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assetLeg = _assetLeg();
    final account = assetLeg == null ? null : accountsById[assetLeg.accountId];
    final currency = assetLeg == null
        ? null
        : currenciesByCode[assetLeg.currencyCode];

    final deleted = transaction.deleted;
    final titleText = transaction.description.isNotEmpty
        ? transaction.description
        : (assetLeg?.categoryPath?.value ?? _typeLabel(transaction.type));
    final titleStyle = deleted
        ? theme.textTheme.bodyLarge?.copyWith(
            decoration: TextDecoration.lineThrough,
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyLarge;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _typeColor(transaction.type, theme)
            .withValues(alpha: 0.15),
        foregroundColor: _typeColor(transaction.type, theme),
        child: Icon(_typeIcon(transaction.type)),
      ),
      title: Text(titleText, style: titleStyle, overflow: TextOverflow.ellipsis),
      subtitle: account == null ? null : Text(account.path),
      trailing: SizedBox(
        width: 140,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: assetLeg == null
                  ? const SizedBox.shrink()
                  : Text(
                      formatMoney(assetLeg.amount, currency),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _amountColor(transaction.type,
                            assetLeg.amount, theme),
                      ),
                    ),
            ),
            PopupMenuButton<_RowAction>(
              onSelected: (a) {
                switch (a) {
                  case _RowAction.edit:
                    onEdit();
                  case _RowAction.delete:
                    onDelete();
                  case _RowAction.restore:
                    onRestore();
                }
              },
              itemBuilder: (_) => [
                if (!deleted)
                  const PopupMenuItem(
                    value: _RowAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                    ),
                  ),
                if (!deleted)
                  const PopupMenuItem(
                    value: _RowAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                if (deleted)
                  const PopupMenuItem(
                    value: _RowAction.restore,
                    child: ListTile(
                      leading: Icon(Icons.restore),
                      title: Text('Restore'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      onTap: deleted ? null : onTap,
    );
  }

  /// Pick the "asset side" leg: for expense/income it's the leg whose account
  /// is *not* the built-in sink/source. For transfers either leg works — by
  /// convention we show the outflow (negative amount).
  Leg? _assetLeg() {
    if (transaction.legs.isEmpty) return null;
    if (transaction.type == TransactionType.transfer) {
      return transaction.legs.firstWhere(
          (l) => l.amount < Decimal.zero,
          orElse: () => transaction.legs.first);
    }
    return transaction.legs.firstWhere(
      (l) => l.accountId != Account.expenseId && l.accountId != Account.incomeId,
      orElse: () => transaction.legs.first,
    );
  }
}

IconData _typeIcon(TransactionType t) => switch (t) {
      TransactionType.expense => Icons.north_east,
      TransactionType.income => Icons.south_west,
      TransactionType.transfer => Icons.swap_horiz,
    };

Color _typeColor(TransactionType t, ThemeData theme) => switch (t) {
      TransactionType.expense => Colors.red,
      TransactionType.income => Colors.green,
      TransactionType.transfer => theme.colorScheme.primary,
    };

Color _amountColor(TransactionType t, Decimal amount, ThemeData theme) =>
    switch (t) {
      TransactionType.expense => Colors.red.shade700,
      TransactionType.income => Colors.green.shade700,
      TransactionType.transfer => theme.colorScheme.onSurface,
    };

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      TransactionType.transfer => 'Transfer',
    };

enum _RowAction { edit, delete, restore }
