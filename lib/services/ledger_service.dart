import 'package:decimal/decimal.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/ids.dart';
import '../models/transaction.dart';
import '../models/validation_result.dart';

/// Single entry point for the double-entry engine.
///
/// Owns the four append-only JSONL repositories internally. External
/// callers get read-only access via `ledger.accounts`, `ledger.categories`,
/// `ledger.currencies`, `ledger.transactions`. All writes must go through
/// the service-level helpers (`saveAccount`, `saveTransaction`, …) so
/// validation, chain-pointer maintenance (Phase 1.6), and aggregator
/// updates (Phase 1.8) can be enforced uniformly.
class LedgerService {
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final CurrencyRepository _currencies;
  final TransactionRepository _transactions;

  LedgerService({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
  })  : _accounts = AccountRepository(filePath: accountsPath),
        _categories = CategoryRepository(filePath: categoriesPath),
        _currencies = CurrencyRepository(filePath: currenciesPath),
        _transactions = TransactionRepository(filePath: transactionsPath);

  ReadOnlyRepository<AccountId, Account> get accounts => _accounts;
  ReadOnlyRepository<CategoryId, Category> get categories => _categories;
  ReadOnlyRepository<CurrencyId, Currency> get currencies => _currencies;
  ReadOnlyRepository<TransactionId, Transaction> get transactions =>
      _transactions;

  Future<void> saveAccount(Account account) => _accounts.save(account);
  Future<void> saveAllAccounts(List<Account> accounts) =>
      _accounts.saveAll(accounts);
  Future<void> deleteAccount(Account account) => _accounts.delete(account);

  Future<void> saveCategory(Category category) => _categories.save(category);
  Future<void> saveAllCategories(List<Category> categories) =>
      _categories.saveAll(categories);
  Future<void> deleteCategory(Category category) =>
      _categories.delete(category);

  Future<void> saveCurrency(Currency currency) => _currencies.save(currency);
  Future<void> saveAllCurrencies(List<Currency> currencies) =>
      _currencies.saveAll(currencies);
  Future<void> deleteCurrency(Currency currency) =>
      _currencies.delete(currency);

  /// Validates [tx] and saves it if valid. Returns the validation result;
  /// no write happens on failure.
  Future<ValidationResult> saveTransaction(Transaction tx) async {
    final result = tx.validate();
    if (!result.isValid) return result;
    await _transactions.save(tx);
    return result;
  }

  /// Validates every transaction first; if any is invalid, returns the
  /// first failure and writes nothing. On success, writes all and
  /// returns [ValidationResult.ok].
  Future<ValidationResult> saveAllTransactions(List<Transaction> txs) async {
    for (final tx in txs) {
      final result = tx.validate();
      if (!result.isValid) return result;
    }
    await _transactions.saveAll(txs);
    return ValidationResult.ok();
  }

  Future<void> deleteTransaction(Transaction tx) => _transactions.delete(tx);

  /// Computes balances per account per currency over every transaction
  /// in the journal (including soft-deleted ones, by current design).
  ///
  /// Phase 1.7 will introduce a filter+group `query` API; until then,
  /// this remains the only read-side aggregation on `LedgerService`.
  Future<Map<AccountId, Map<CurrencyCode, Decimal>>> computeBalances() async {
    final txs = await _transactions.getAll();
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
