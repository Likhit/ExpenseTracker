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
import '../models/leg.dart';
import '../models/transaction.dart';
import '../models/validation_result.dart';
import 'query/ledger_filter.dart';
import 'query/ledger_group.dart';
import 'query/ledger_stats.dart';

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

  /// Filters legs by [filter] and optionally nests them into a stats tree
  /// along [groupBy]. Returns the matching transactions (deduplicated)
  /// alongside a [GroupedStats] tree whose root aggregates every matched
  /// leg and whose children partition them per dimension.
  ///
  /// Consumes the transaction repo as a stream so non-matching rows are
  /// discarded without ever sitting in memory; only legs that survive
  /// [filter] are held to build the [GroupedStats] tree.
  Future<QueryResult> query(
    LedgerFilter filter, {
    List<GroupDimension> groupBy = const [],
  }) async {
    final matchedTxs = <Transaction>[];
    final matchedLegs = <({Leg leg, Transaction tx})>[];

    await for (final tx in _transactions.streamAll()) {
      final legs = filter.apply(tx);
      if (legs.isEmpty) continue;
      matchedTxs.add(tx);
      for (final leg in legs) {
        matchedLegs.add((leg: leg, tx: tx));
      }
    }

    final stats = GroupedStats(
      key: const GroupKey.none(),
      stats: _statsOf(matchedLegs),
      children: _buildChildren(matchedLegs, groupBy),
    );
    return QueryResult(transactions: matchedTxs, stats: stats);
  }

  List<GroupedStats> _buildChildren(
    List<({Leg leg, Transaction tx})> legs,
    List<GroupDimension> groupBy,
  ) {
    if (groupBy.isEmpty || legs.isEmpty) return const [];
    final dim = groupBy.first;
    final rest = groupBy.sublist(1);

    // Insertion-ordered: groups appear in the order their first leg was
    // encountered. Deterministic given the input stream order.
    final buckets = <GroupKey, List<({Leg leg, Transaction tx})>>{};
    for (final ml in legs) {
      final key = dim.keyFor(ml.leg, ml.tx);
      buckets.putIfAbsent(key, () => []).add(ml);
    }

    return [
      for (final entry in buckets.entries)
        GroupedStats(
          key: entry.key,
          stats: _statsOf(entry.value),
          children: _buildChildren(entry.value, rest),
        ),
    ];
  }

  Stats _statsOf(List<({Leg leg, Transaction tx})> legs) {
    final sums = <CurrencyCode, Decimal>{};
    for (final ml in legs) {
      sums.update(
        ml.leg.currencyCode,
        (existing) => existing + ml.leg.amount,
        ifAbsent: () => ml.leg.amount,
      );
    }
    return Stats(count: legs.length, sumByCurrency: sums);
  }

  /// Convenience: balances per account per currency. Soft-deleted
  /// transactions are excluded by default (same default as [query]).
  Future<Map<AccountId, Map<CurrencyCode, Decimal>>> computeBalances() async {
    final result = await query(
      const LedgerFilter(),
      groupBy: const [GroupDimension.byAccount(), GroupDimension.byCurrency()],
    );
    final balances = <AccountId, Map<CurrencyCode, Decimal>>{};
    for (final accountNode in result.stats.children) {
      final accountKey = accountNode.key as AccountKey;
      final perCurrency = <CurrencyCode, Decimal>{};
      for (final currencyNode in accountNode.children) {
        final currencyKey = currencyNode.key as CurrencyKey;
        final sum = currencyNode.stats.sumByCurrency[currencyKey.code];
        if (sum != null) perCurrency[currencyKey.code] = sum;
      }
      balances[accountKey.id] = perCurrency;
    }
    return balances;
  }
}
