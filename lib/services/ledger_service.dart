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
///
/// Construction goes through [LedgerService.create] (async) which
/// guarantees the built-in Expense and Income accounts exist on disk
/// before returning. Every expense leg uses [Account.expenseId] and
/// every income leg uses [Account.incomeId]; callers never create
/// those accounts manually.
class LedgerService {
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final CurrencyRepository _currencies;
  final TransactionRepository _transactions;

  LedgerService._({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
  })  : _accounts = AccountRepository(filePath: accountsPath),
        _categories = CategoryRepository(filePath: categoriesPath),
        _currencies = CurrencyRepository(filePath: currenciesPath),
        _transactions = TransactionRepository(filePath: transactionsPath);

  /// Constructs a [LedgerService] over the given JSONL paths and ensures
  /// the built-in Expense and Income accounts are present on disk
  /// (creating them with stable ids the first time around).
  static Future<LedgerService> create({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
  }) async {
    final ledger = LedgerService._(
      accountsPath: accountsPath,
      categoriesPath: categoriesPath,
      currenciesPath: currenciesPath,
      transactionsPath: transactionsPath,
    );
    await ledger._ensureBuiltinAccounts();
    return ledger;
  }

  Future<void> _ensureBuiltinAccounts() async {
    final existingIds = (await _accounts.getAll()).map((a) => a.id).toSet();
    final now = DateTime.now();
    final missing = <Account>[
      if (!existingIds.contains(Account.expenseId))
        Account(
          id: Account.expenseId,
          path: 'Expense',
          type: AccountType.expense,
          createdAt: now,
        ),
      if (!existingIds.contains(Account.incomeId))
        Account(
          id: Account.incomeId,
          path: 'Income',
          type: AccountType.income,
          createdAt: now,
        ),
    ];
    if (missing.isNotEmpty) await _accounts.saveAll(missing);
  }

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

  /// Filters legs by [filter] and optionally nests them along [groupBy]
  /// into a [QueryResult] tree. With no `groupBy`, the result is a single
  /// [LeafResult] holding every matching transaction and the total stats.
  /// With `groupBy`, the result is a [NodeResult] rooted at `GroupKey.none()`
  /// whose subtree partitions the matching legs along each dimension —
  /// leaves carry the per-bucket transactions and stats; intermediate
  /// nodes derive theirs from the subtree.
  ///
  /// Consumes the transaction repo as a stream so non-matching rows are
  /// discarded without ever sitting in memory; only legs that survive
  /// [filter] are held while the tree is built.
  Future<QueryResult> query(
    LedgerFilter filter, {
    List<GroupDimension> groupBy = const [],
  }) async {
    final matchedLegs = <({Leg leg, Transaction tx})>[];
    await for (final tx in _transactions.streamAll()) {
      final legs = filter.apply(tx);
      if (legs.isEmpty) continue;
      for (final leg in legs) {
        matchedLegs.add((leg: leg, tx: tx));
      }
    }
    return _buildTree(matchedLegs, groupBy, const GroupKey.none());
  }

  QueryResult _buildTree(
    List<({Leg leg, Transaction tx})> legs,
    List<GroupDimension> remaining,
    GroupKey key,
  ) {
    if (remaining.isEmpty) {
      return QueryResult.leaf(
        key: key,
        transactions: _uniqueTxs(legs),
        stats: _statsOf(legs),
      );
    }
    final dim = remaining.first;
    final rest = remaining.sublist(1);

    // Insertion-ordered: groups appear in the order their first leg was
    // encountered. Deterministic given the input stream order.
    final buckets = <GroupKey, List<({Leg leg, Transaction tx})>>{};
    for (final ml in legs) {
      final k = dim.keyFor(ml.leg, ml.tx);
      buckets.putIfAbsent(k, () => []).add(ml);
    }

    final children = [
      for (final entry in buckets.entries)
        _buildTree(entry.value, rest, entry.key),
    ];
    return QueryResult.node(
      key: key,
      children: children,
      stats: combineStats(children.map((c) => c.stats)),
    );
  }

  Stats _statsOf(List<({Leg leg, Transaction tx})> legs) {
    var stats = Stats.defaults();
    for (final ml in legs) {
      stats = stats.apply(ml.leg, ml.tx);
    }
    return stats;
  }

  List<Transaction> _uniqueTxs(List<({Leg leg, Transaction tx})> legs) {
    final seen = <TransactionId>{};
    final result = <Transaction>[];
    for (final ml in legs) {
      if (seen.add(ml.tx.id)) result.add(ml.tx);
    }
    return result;
  }

  /// Convenience: balances per account per currency. Soft-deleted
  /// transactions are excluded by default (same default as [query]).
  Future<Map<AccountId, Map<CurrencyCode, Decimal>>> computeBalances() async {
    final result = await query(
      const LedgerFilter(),
      groupBy: const [GroupDimension.byAccount(), GroupDimension.byCurrency()],
    );
    final balances = <AccountId, Map<CurrencyCode, Decimal>>{};
    for (final accountNode in result.children) {
      final accountKey = accountNode.key as AccountKey;
      final perCurrency = <CurrencyCode, Decimal>{};
      for (final currencyLeaf in accountNode.children) {
        final currencyKey = currencyLeaf.key as CurrencyKey;
        final sum = currencyLeaf.stats.sumByCurrency[currencyKey.code];
        if (sum != null) perCurrency[currencyKey.code] = sum;
      }
      balances[accountKey.id] = perCurrency;
    }
    return balances;
  }
}
