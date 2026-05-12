import 'package:decimal/decimal.dart';

import '../models/ids.dart';
import '../models/transaction.dart';

/// Computes account balances from a journal of transactions.
class LedgerService {
  /// Computes balances per account per currency.
  ///
  /// Returns a map of accountId -> (currencyCode -> balance).
  /// Positive balance = net debit, negative = net credit.
  Map<AccountId, Map<CurrencyCode, Decimal>> computeBalances(
      List<Transaction> transactions) {
    final balances = <AccountId, Map<CurrencyCode, Decimal>>{};

    for (final tx in transactions) {
      for (final leg in tx.legs) {
        balances
            .putIfAbsent(leg.accountId, () => {})
            .update(
              leg.currencyCode,
              (existing) => existing + leg.amount,
              ifAbsent: () => leg.amount,
            );
      }
    }

    return balances;
  }
}
