import 'package:decimal/decimal.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/ids.dart';

/// Single entry point for the double-entry engine.
///
/// Owns the four append-only JSONL repositories and exposes them as
/// `ledger.accounts`, `ledger.categories`, `ledger.currencies`, and
/// `ledger.transactions`. All writes are expected to go through this
/// service so later phases can hook in chain-pointer maintenance
/// (Phase 1.6) and aggregator updates (Phase 1.8).
class LedgerService {
  final AccountRepository accounts;
  final CategoryRepository categories;
  final CurrencyRepository currencies;
  final TransactionRepository transactions;

  LedgerService({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
  })  : accounts = AccountRepository(filePath: accountsPath),
        categories = CategoryRepository(filePath: categoriesPath),
        currencies = CurrencyRepository(filePath: currenciesPath),
        transactions = TransactionRepository(filePath: transactionsPath);

  /// Computes balances per account per currency over every transaction
  /// in the journal (including soft-deleted ones, by current design).
  ///
  /// Phase 1.7 will introduce a filter+group `query` API; until then,
  /// this remains the only read-side aggregation on `LedgerService`.
  Future<Map<AccountId, Map<CurrencyCode, Decimal>>> computeBalances() async {
    final txs = await transactions.getAll();
    final balances = <AccountId, Map<CurrencyCode, Decimal>>{};
    for (final tx in txs) {
      for (final leg in tx.legs) {
        balances.putIfAbsent(leg.accountId, () => {}).update(
              leg.currencyCode,
              (existing) => existing + leg.amount,
              ifAbsent: () => leg.amount,
            );
      }
    }
    return balances;
  }
}
