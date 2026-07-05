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
    final isTransfer = transaction.type == TransactionType.transfer;
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

    // Transfers span two user accounts, so show both sides ("From → To").
    // Expense/income only touch one asset account, so show just that path.
    final String? subtitleText;
    if (isTransfer) {
      final from = _transferLeg(negative: true);
      final to = _transferLeg(negative: false);
      final fromName = from == null ? '?' : accountsById[from.accountId]?.path;
      final toName = to == null ? '?' : accountsById[to.accountId]?.path;
      subtitleText = '${fromName ?? '?'} → ${toName ?? '?'}';
    } else {
      subtitleText = account?.path;
    }

    // Transfers are neither income nor expense — money just moves between the
    // user's own accounts — so render them unsigned and in a muted color.
    final amountText = assetLeg == null
        ? null
        : formatMoney(
            isTransfer ? assetLeg.amount.abs() : assetLeg.amount, currency);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _typeColor(transaction.type, theme)
            .withValues(alpha: 0.15),
        foregroundColor: _typeColor(transaction.type, theme),
        child: Icon(_typeIcon(transaction.type)),
      ),
      title: Text(titleText, style: titleStyle, overflow: TextOverflow.ellipsis),
      subtitle: subtitleText == null ? null : Text(subtitleText),
      trailing: SizedBox(
        width: 140,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: amountText == null
                  ? const SizedBox.shrink()
                  : Text(
                      amountText,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _amountColor(transaction.type,
                            assetLeg!.amount, theme),
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
      return _transferLeg(negative: true) ?? transaction.legs.first;
    }
    return transaction.legs.firstWhere(
      (l) => l.accountId != Account.expenseId && l.accountId != Account.incomeId,
      orElse: () => transaction.legs.first,
    );
  }

  /// The outflow (`negative: true`) or inflow leg of a transfer, or null if the
  /// transaction has no leg of that sign.
  Leg? _transferLeg({required bool negative}) {
    for (final l in transaction.legs) {
      if (negative ? l.amount < Decimal.zero : l.amount > Decimal.zero) {
        return l;
      }
    }
    return null;
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
      TransactionType.transfer => theme.colorScheme.onSurfaceVariant,
    };

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      TransactionType.transfer => 'Transfer',
    };

enum _RowAction { edit, delete, restore }
