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
import 'query/ledger_filter.dart';
import 'query/ledger_group.dart';
import 'query/ledger_stats.dart';
import 'query/ledger_view.dart';

/// Single entry point for the double-entry engine.
///
/// Owns the four append-only JSONL repositories internally. External
/// callers get read-only access via `ledger.accounts`, `ledger.categories`,
/// `ledger.currencies`, `ledger.transactions`. All writes go through the
/// generic `save` / `delete` methods below — they validate (when the entity
/// opts into [Validatable]) and dispatch to the right repository based on the
/// entity type. After a transaction write, every registered [LedgerView] is
/// updated with the (pre-save, post-save) pair.
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

  /// Named maintained views, keyed by name for O(1) lookup.
  final Map<String, LedgerView> _viewsByName = {};

  LedgerService._({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
  })  : _accounts = AccountRepository(filePath: accountsPath),
        _categories = CategoryRepository(filePath: categoriesPath),
        _currencies = CurrencyRepository(filePath: currenciesPath),
        _transactions = TransactionRepository(filePath: transactionsPath);

  /// Constructs a [LedgerService] over the given JSONL paths. Ensures the
  /// built-in Expense and Income accounts are present on disk before
  /// returning. Register maintained views afterwards with [register].
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

  /// Registers a maintained [LedgerView] under [name] and seeds it by
  /// replaying the journal once. Subsequent saves keep it fresh via the
  /// push-update path. Throws [ArgumentError] on a duplicate name. Returns
  /// the registered view, whose current tree is read via [LedgerView.result].
  Future<LedgerView> register({
    required String name,
    LedgerFilter filter = const LedgerFilter(),
    List<GroupDimension> groupBy = const [],
    Stats? template,
  }) async {
    if (_viewsByName.containsKey(name)) {
      throw ArgumentError('Duplicate view name: "$name"');
    }
    final view = LedgerView(
      name: name,
      filter: filter,
      groupBy: groupBy,
      template: template,
    );
    view.seed(await _transactions.getAll());
    _viewsByName[name] = view;
    return view;
  }

  /// The maintained view registered under [name]. Throws [ArgumentError] if
  /// no such view exists (a lookup miss is a programming error, not a value).
  /// Read its current tree via [LedgerView.result].
  LedgerView viewResult(String name) {
    final view = _viewsByName[name];
    if (view == null) {
      throw ArgumentError.value(name, 'name', 'No view registered');
    }
    return view;
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
    for (final account in missing) {
      await _accounts.save(account);
    }
  }

  ReadOnlyRepository<AccountId, Account> get accounts => _accounts;
  ReadOnlyRepository<CategoryId, Category> get categories => _categories;
  ReadOnlyRepository<CurrencyId, Currency> get currencies => _currencies;
  ReadOnlyRepository<TransactionId, Transaction> get transactions =>
      _transactions;

  /// Validates [entity] (when it implements [Validatable]) and persists
  /// it to the matching repository. Returns the validation result; on
  /// failure, no write happens. After a successful [Transaction] save,
  /// every registered view receives the (pre-save, post-save) pair so
  /// it can update its maintained tree.
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
        final old = await _transactions.get(t.id);
        await _transactions.save(t);
        _notifyViews(old, t);
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
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
        final old = await _transactions.get(t.id);
        final deleted = await _transactions.delete(t);
        _notifyViews(old, deleted);
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
    }
  }

  void _notifyViews(Transaction? old, Transaction newVersion) {
    for (final view in _viewsByName.values) {
      view.applySave(old, newVersion);
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
  /// Consumes the transaction repo as a stream, folding each transaction into
  /// the result tree via [QueryResult.add] — the same fold `LedgerView` uses —
  /// so non-matching rows are discarded without ever sitting in memory.
  Future<QueryResult> query(
    LedgerFilter filter, {
    List<GroupDimension> groupBy = const [],
  }) async {
    final template = Stats.defaults();
    final result = QueryResult.empty(groupBy, template);
    await for (final tx in _transactions.streamAll()) {
      result.add(tx, filter, groupBy, template);
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
