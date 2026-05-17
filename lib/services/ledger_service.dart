import 'package:decimal/decimal.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/storage/jsonl_storable.dart';
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
/// `ledger.currencies`, `ledger.transactions`. All writes go through the
/// generic `save` / `saveAll` / `delete` methods below — they validate
/// (when the entity opts into [Validatable]) and dispatch to the right
/// repository based on the entity type. Phase 1.8 (aggregator updates)
/// will hook into these same methods.
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

  /// Validates [entity] (when it implements [Validatable]) and persists
  /// it to the matching repository. Returns the validation result; on
  /// failure, no write happens.
  Future<ValidationResult> save<T extends JsonlEntity>(T entity) async {
    if (entity is Validatable) {
      final result = (entity as Validatable).validate();
      if (!result.isValid) return result;
    }
    switch (entity) {
      case Account a:
        await _accounts.save(a);
      case Category c:
        await _categories.save(c);
      case Currency cur:
        await _currencies.save(cur);
      case Transaction t:
        await _transactions.save(t);
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
    }
    return ValidationResult.ok();
  }

  /// Validates every entity first; if any is invalid, returns the first
  /// failure and writes nothing. Otherwise persists all to the matching
  /// repository. The list is assumed to be homogeneous in entity type.
  Future<ValidationResult> saveAll<T extends JsonlEntity>(
      List<T> entities) async {
    if (entities.isEmpty) return ValidationResult.ok();
    for (final e in entities) {
      if (e is Validatable) {
        final result = (e as Validatable).validate();
        if (!result.isValid) return result;
      }
    }
    switch (entities.first) {
      case Account _:
        await _accounts.saveAll(entities.cast<Account>());
      case Category _:
        await _categories.saveAll(entities.cast<Category>());
      case Currency _:
        await _currencies.saveAll(entities.cast<Currency>());
      case Transaction _:
        await _transactions.saveAll(entities.cast<Transaction>());
      default:
        throw StateError(
            'Unsupported entity type: ${entities.first.runtimeType}');
    }
    return ValidationResult.ok();
  }

  /// Soft-deletes [entity] by appending a new version with `deleted: true`.
  Future<void> delete<T extends JsonlEntity>(T entity) async {
    switch (entity) {
      case Account a:
        await _accounts.delete(a);
      case Category c:
        await _categories.delete(c);
      case Currency cur:
        await _currencies.delete(cur);
      case Transaction t:
        await _transactions.delete(t);
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
    }
  }

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
