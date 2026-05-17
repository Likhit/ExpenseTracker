import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import '../query/ledger_filter.dart';
import '../query/ledger_group.dart';
import '../query/ledger_stats.dart';

/// Definition of a named, kept-fresh aggregation over the journal.
///
/// A [LedgerView] is just configuration — a (filter, groupBy, stats
/// template) triple plus a human-friendly name. The mutable maintained
/// state lives in [LedgerViewState], constructed and updated by
/// `LedgerService` as transactions are saved.
///
/// Typical use:
/// ```dart
/// final ledger = await LedgerService.create(
///   ...,
///   views: [
///     LedgerView(
///       name: 'balances',
///       groupBy: [GroupDimension.byAccount(), GroupDimension.byCurrency()],
///     ),
///     LedgerView(
///       name: 'monthly-spending',
///       filter: LedgerFilter(
///         types: {TransactionType.expense},
///         excludeAccounts: {Account.expenseId},
///       ),
///       groupBy: [GroupDimension.byTime(TimeBucket.month), GroupDimension.byCategory()],
///     ),
///   ],
/// );
///
/// final balances = ledger.viewResult('balances');
/// ```
class LedgerView {
  final String name;
  final LedgerFilter filter;
  final List<GroupDimension> groupBy;

  /// Empty-state template that defines which [Stat] kinds each leaf
  /// tracks. Defaults to [Stats.defaults] (count + sumByCurrency).
  final Stats template;

  LedgerView({
    required this.name,
    this.filter = const LedgerFilter(),
    this.groupBy = const [],
    Stats? template,
  }) : template = template ?? Stats.defaults();
}

/// Mutable maintained state for one registered [LedgerView]. Lives
/// inside `LedgerService`; production code reads the public
/// [QueryResult] via [current] and never touches the mutators directly.
class LedgerViewState {
  final LedgerView view;
  final Map<_LeafKey, _LeafState> _leaves = {};

  LedgerViewState(this.view);

  /// Wipes the maintained state and replays [txs] through the view.
  /// Called on construction and on `ledger.rebuildViews()`.
  void seed(Iterable<Transaction> txs) {
    _leaves.clear();
    for (final tx in txs) {
      applySave(null, tx);
    }
  }

  /// Diffs [oldVersion] vs [newVersion] and updates the maintained
  /// state accordingly. Either may be null:
  /// - oldVersion == null: brand-new transaction; apply [newVersion]'s
  ///   matching legs.
  /// - newVersion's matching legs may be empty (e.g. it's now
  ///   soft-deleted and the view's filter excludes deleted): only the
  ///   revert path runs.
  ///
  /// The revert path applies the old leg with `tx.deleted` flipped, so
  /// the per-stat `apply` convention (deleted = subtract) cancels the
  /// previously-added contribution.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    // Track which (leaf, txId) pairs the old version occupies so we
    // can drop the cached Transaction from any leaf the new version
    // no longer touches.
    final oldLeafKeys = <_LeafKey>{};
    if (oldVersion != null) {
      for (final leg in view.filter.apply(oldVersion)) {
        final path = _pathFor(leg, oldVersion);
        oldLeafKeys.add(path);
        final state = _leaves[path];
        if (state == null) continue;
        state.stats = state.stats.apply(leg, _flipDeleted(oldVersion));
      }
    }

    final newLeafKeys = <_LeafKey>{};
    for (final leg in view.filter.apply(newVersion)) {
      final path = _pathFor(leg, newVersion);
      newLeafKeys.add(path);
      final state = _leaves.putIfAbsent(
        path,
        () => _LeafState(stats: view.template),
      );
      state.stats = state.stats.apply(leg, newVersion);
      state.transactions[newVersion.id] = newVersion;
    }

    // Any leaf that the old version was in but the new isn't: drop
    // the cached Transaction for that id. Don't drop the leaf itself
    // here — another transaction may still be contributing.
    if (oldVersion != null) {
      for (final path in oldLeafKeys.difference(newLeafKeys)) {
        final state = _leaves[path];
        if (state == null) continue;
        state.transactions.remove(oldVersion.id);
      }
    }

    // Garbage-collect empty leaves so the tree only includes buckets
    // that currently hold a transaction.
    _leaves.removeWhere((_, state) => state.transactions.isEmpty);
  }

  /// Current snapshot of the maintained tree. Builds an immutable
  /// [QueryResult] from the internal leaf map; safe for callers to
  /// hold or transform without affecting future updates.
  QueryResult get current {
    if (view.groupBy.isEmpty) {
      final state = _leaves[const _LeafKey(<GroupKey>[])];
      return QueryResult.leaf(
        key: const GroupKey.none(),
        transactions: state?.transactions.values ?? const <Transaction>[],
        stats: state?.stats ?? view.template,
      );
    }
    if (_leaves.isEmpty) {
      return QueryResult.node(
        key: const GroupKey.none(),
        children: const [],
        stats: view.template,
      );
    }
    return _buildSubtree(0, const GroupKey.none(), _leaves.entries.toList());
  }

  QueryResult _buildSubtree(
    int depth,
    GroupKey nodeKey,
    List<MapEntry<_LeafKey, _LeafState>> entries,
  ) {
    if (depth == view.groupBy.length) {
      // Every entry at this depth shares the full path, so they all
      // collapse to one leaf. (The map key dedups on path.)
      final state = entries.single.value;
      return QueryResult.leaf(
        key: nodeKey,
        transactions: state.transactions.values,
        stats: state.stats,
      );
    }
    final buckets = <GroupKey, List<MapEntry<_LeafKey, _LeafState>>>{};
    for (final entry in entries) {
      final key = entry.key.path[depth];
      buckets.putIfAbsent(key, () => []).add(entry);
    }
    final children = [
      for (final bucket in buckets.entries)
        _buildSubtree(depth + 1, bucket.key, bucket.value),
    ];
    return QueryResult.node(
      key: nodeKey,
      children: children,
      stats: combineStats(children.map((c) => c.stats)),
    );
  }

  _LeafKey _pathFor(Leg leg, Transaction tx) => _LeafKey([
        for (final dim in view.groupBy) dim.keyFor(leg, tx),
      ]);

  Transaction _flipDeleted(Transaction tx) =>
      tx.deleted ? tx.copyWith(deleted: false) : tx.copyWith(deleted: true);
}

class _LeafState {
  Stats stats;
  final Map<TransactionId, Transaction> transactions = {};

  _LeafState({required this.stats});
}

/// Wrapper around `List<GroupKey>` with value-based equality so it can
/// serve as a `Map` key in [LedgerViewState].
class _LeafKey {
  final List<GroupKey> path;

  const _LeafKey(this.path);

  @override
  bool operator ==(Object other) {
    if (other is! _LeafKey) return false;
    if (path.length != other.path.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (path[i] != other.path[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(path);
}
