import 'dart:async';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/storage/file_sync.dart';
import '../data/storage/jsonl_storable.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/ids.dart';
import '../models/line_id.dart';
import '../models/transaction.dart';
import '../models/validation_result.dart';
import 'query/ledger_filter.dart';
import 'query/ledger_group.dart';
import 'ledger_state.dart';
import 'query/ledger_stats.dart';
import 'query/ledger_view.dart';
import 'query/view_store.dart';

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

  /// Optional persistence for maintained views. When present, snapshots are
  /// written through after every transaction write and restored on [register].
  final ViewStore? _viewStore;

  /// Ready, or blocked on unresolved sync conflicts. See [state].
  LedgerState _state = const LedgerReady();

  /// Fires after every successful write ([save]/[delete]), [sync], and
  /// [resolveConflicts] — used by reactivity layers (e.g. Riverpod providers)
  /// to re-read the four repositories' state. Per-view updates also fire on
  /// the corresponding [LedgerView.changes] stream.
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  LedgerService._({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
    required ViewStore? viewStore,
  })  : _accounts = AccountRepository(filePath: accountsPath),
        _categories = CategoryRepository(filePath: categoriesPath),
        _currencies = CurrencyRepository(filePath: currenciesPath),
        _transactions = TransactionRepository(filePath: transactionsPath),
        _viewStore = viewStore;

  /// Constructs a [LedgerService] over the given JSONL paths. Ensures the
  /// built-in Expense and Income accounts are present on disk before
  /// returning. Register maintained views afterwards with [register]; pass a
  /// [viewStore] to persist them across restarts.
  static Future<LedgerService> create({
    required String accountsPath,
    required String categoriesPath,
    required String currenciesPath,
    required String transactionsPath,
    ViewStore? viewStore,
  }) async {
    final ledger = LedgerService._(
      accountsPath: accountsPath,
      categoriesPath: categoriesPath,
      currenciesPath: currenciesPath,
      transactionsPath: transactionsPath,
      viewStore: viewStore,
    );
    await ledger._ensureBuiltinAccounts();
    await ledger.sync();
    return ledger;
  }

  /// Current state: [LedgerReady], or [LedgerConflicted] while a sync merge is
  /// awaiting [resolveConflicts].
  LedgerState get state => _state;

  /// Registers a maintained [LedgerView] under [name]. If a [viewStore] holds
  /// a snapshot whose watermark still matches the journal tip, the view is
  /// restored from it (no replay); otherwise it is seeded by replaying the
  /// journal and the fresh snapshot is persisted. Subsequent saves keep it
  /// fresh via the push-update path. Throws [ArgumentError] on a duplicate
  /// name. Returns the view, whose tree is read via [LedgerView.result].
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

    final store = _viewStore;
    final tip = await _transactions.currentTip();
    final restored = store == null ? null : await store.load(name);
    // Adopt the restored tree when the snapshot is for the same config (a
    // view's identity is its name *and* its config), then bring it current by
    // replaying only the journal appends after its watermark — no full
    // rebuild. A config mismatch (or no snapshot) falls back to a full seed.
    if (restored != null && _sameConfig(restored.view, view)) {
      view.restore(restored.view.result);
      await _replayInto(view, restored.watermark);
    } else {
      view.seed(await _transactions.getAll());
    }
    await store?.save(view, tip);

    _viewsByName[name] = view;
    return view;
  }

  /// Whether two views share the same `(filter, groupBy, template)` — the part
  /// of a view's identity beyond its name. Compared by value; `Set` equality
  /// in [LedgerFilter] is order-independent.
  static bool _sameConfig(LedgerView a, LedgerView b) =>
      a.filter == b.filter &&
      const ListEquality<GroupDimension>().equals(a.groupBy, b.groupBy) &&
      a.template == b.template;

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
    _ensureReady();
    if (entity is Validatable) {
      final result = (entity as Validatable).validate();
      if (!result.isValid) return result;
    }
    await _write(entity);
    _changesController.add(null);
    return ValidationResult.ok();
  }

  /// Soft-deletes [entity] by appending a new version with `deleted: true`.
  Future<void> delete<T extends JsonlEntity>(T entity) async {
    _ensureReady();
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
        await _persistViews();
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
    }
    _changesController.add(null);
  }

  /// Appends [entity] to its repository and, for transactions, updates and
  /// persists the maintained views. The shared write path behind [save] and
  /// conflict resolution; it does not validate or check [state].
  Future<void> _write<T extends JsonlEntity>(T entity) async {
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
        await _persistViews();
      default:
        throw StateError('Unsupported entity type: ${entity.runtimeType}');
    }
  }

  void _ensureReady() {
    if (_state is LedgerConflicted) {
      throw StateError(
          'Ledger has unresolved sync conflicts; call resolveConflicts first');
    }
  }

  void _notifyViews(Transaction? old, Transaction newVersion) {
    for (final view in _viewsByName.values) {
      view.applySave(old, newVersion);
    }
  }

  /// Write-through: persist every maintained view at the current journal tip.
  /// No-op without a [ViewStore] or when no views are registered.
  Future<void> _persistViews() async {
    final store = _viewStore;
    if (store == null || _viewsByName.isEmpty) return;
    final tip = await _transactions.currentTip();
    for (final view in _viewsByName.values) {
      await store.save(view, tip);
    }
  }

  /// Scans the sync folder for conflict copies of each repository file and
  /// merges them in (see `Repository.merge`), then brings any registered views
  /// current over the transactions the merge appended. Run automatically by
  /// [create]; call again when a watcher reports the folder changed.
  ///
  /// If a merge surfaced entities edited on both sides, the ledger moves to
  /// [LedgerConflicted] and rejects writes until [resolveConflicts]. The merged
  /// tree provisionally reflects the other side's version of each conflict.
  Future<void> sync() async {
    final tipBefore = await _transactions.currentTip();
    final conflicts = <EntityConflict>[
      ...await _accounts.merge(),
      ...await _categories.merge(),
      ...await _currencies.merge(),
      ...await _transactions.merge(),
    ];
    // Catch up live views over the transactions the merge appended (a no-op at
    // startup, when no views are registered yet — register() catches those up).
    for (final view in _viewsByName.values) {
      await _replayInto(view, tipBefore);
    }
    await _persistViews();
    _state = conflicts.isEmpty ? const LedgerReady() : LedgerConflicted(conflicts);
    _changesController.add(null);
  }

  /// Resolves the conflicts surfaced by a prior [sync]. [resolution] must cover
  /// every conflict in the current [LedgerConflicted] state. Choosing
  /// [ConflictChoice.ours] re-appends our version so it becomes current (the
  /// merge already left theirs as the latest, so [ConflictChoice.theirs] is a
  /// no-op). Returns the ledger to [LedgerReady].
  Future<void> resolveConflicts(
      Map<EntityConflict, ConflictChoice> resolution) async {
    final state = _state;
    if (state is! LedgerConflicted) {
      throw StateError('No conflicts to resolve');
    }
    for (final conflict in state.conflicts) {
      final choice = resolution[conflict];
      if (choice == null) {
        throw ArgumentError('Resolution missing for a conflict');
      }
      if (choice == ConflictChoice.ours) {
        await _write(conflict.ours as JsonlEntity);
      }
    }
    _state = const LedgerReady();
    _changesController.add(null);
  }

  /// Closes the [changes] stream and each registered view's stream.
  Future<void> dispose() async {
    for (final view in _viewsByName.values) {
      await view.dispose();
    }
    await _changesController.close();
  }

  /// Brings [view] current by replaying the transaction appends after [from]
  /// (its watermark) — not a full rebuild. Each append is applied as a
  /// `(prior, new)` pair, where `prior` is that entity's version as of [from],
  /// looked up by scanning back from the watermark. A no-op when [from] is
  /// already the journal tip.
  Future<void> _replayInto(LedgerView view, LineId from) async {
    if (from == await _transactions.currentTip()) return;

    // Walk newest-first: collect appends newer than `from` (the suffix), then
    // the latest pre-`from` version of each suffix id (the `prior`).
    final suffixReversed = <Transaction>[];
    final prior = <TransactionId, Transaction>{};
    var reachedWatermark = false;
    Set<TransactionId> suffixIds = const {};
    await for (final tx in _transactions.appendsReversed()) {
      if (!reachedWatermark) {
        if (tx.lineId == from) {
          reachedWatermark = true;
          suffixIds = {for (final t in suffixReversed) t.id};
          if (suffixIds.isEmpty) break;
        } else {
          suffixReversed.add(tx);
        }
      } else if (suffixIds.contains(tx.id) && !prior.containsKey(tx.id)) {
        prior[tx.id] = tx;
        if (prior.length == suffixIds.length) break;
      }
    }
    // `from` not found (e.g. an empty-journal watermark): the whole chain is the
    // suffix and there are no priors — equivalent to a seed.
    if (!reachedWatermark) suffixIds = {for (final t in suffixReversed) t.id};

    final current = <TransactionId, Transaction>{...prior};
    for (final tx in suffixReversed.reversed) {
      view.applySave(current[tx.id], tx);
      current[tx.id] = tx;
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
