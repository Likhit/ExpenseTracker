import 'package:decimal/decimal.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'stat.dart';

/// Typed container of [Stat] instances. A [Stats] tracks one entry per
/// stat *kind* (one [CountStat], one [SumByCurrencyStat], …). The set
/// of kinds is fixed at construction time — operations like [apply] and
/// [combine] preserve the same shape.
///
/// [Stats] is itself a [Stat] (composite). Its `value` is the [Stats]
/// container itself — callers reach for the typed [get] / convenience
/// getters ([count], [sumByCurrency]) rather than for `value` directly,
/// but any code that takes a [Stat] can take a [Stats] uniformly.
class Stats implements Stat<Stats> {
  final Map<Type, Stat> _stats;

  const Stats._(this._stats);

  /// Builds a [Stats] from a list of empty-state [Stat] instances.
  /// Duplicate kinds are de-duplicated by [Type].
  factory Stats.of(List<Stat> stats) =>
      Stats._({for (final s in stats) s.runtimeType: s});

  /// The default template: count + per-currency sum. Used by
  /// `LedgerService.query` when no custom template is supplied.
  factory Stats.defaults() => Stats.of(const [
        CountStat.empty,
        SumByCurrencyStat.empty,
      ]);

  /// Self — [Stats] is its own value so callers use [get] /
  /// [count] / [sumByCurrency] without indirection.
  @override
  Stats get value => this;

  /// Returns a new [Stats] with [leg] folded into every contained stat.
  @override
  Stats apply(Leg leg, Transaction tx) => Stats._({
        for (final entry in _stats.entries)
          entry.key: entry.value.apply(leg, tx),
      });

  /// Combines this with [other] kind-by-kind. The two must have the
  /// same shape (same set of stat kinds).
  @override
  Stats combine(covariant Stats other) {
    final result = <Type, Stat>{};
    for (final entry in _stats.entries) {
      final otherStat = other._stats[entry.key];
      if (otherStat == null) {
        throw StateError(
            'Cannot combine Stats with different shape: missing ${entry.key}');
      }
      // Dynamic dispatch over the runtime type parameter — Stat<V>.combine
      // accepts another Stat<V>; cast is checked by the variant.
      result[entry.key] = (entry.value as dynamic).combine(otherStat);
    }
    return Stats._(result);
  }

  /// Typed lookup of a stat by its concrete kind.
  T? get<T extends Stat>() => _stats[T] as T?;

  /// Convenience: count from the built-in [CountStat]; 0 if not tracked.
  int get count => get<CountStat>()?.value ?? 0;

  /// Convenience: per-currency sums from the built-in [SumByCurrencyStat];
  /// empty if not tracked.
  Map<CurrencyCode, Decimal> get sumByCurrency =>
      get<SumByCurrencyStat>()?.value ?? const {};

  @override
  bool operator ==(Object other) {
    if (other is! Stats) return false;
    if (_stats.length != other._stats.length) return false;
    for (final entry in _stats.entries) {
      if (entry.value != other._stats[entry.key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
      _stats.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'Stats(${_stats.values.toList()})';
}

/// Tree returned by `LedgerService.query` and maintained by `LedgerView`.
///
/// A [LeafResult] holds its bucket's stats plus a [TransactionSource] — the
/// rows behind the bucket. A [NodeResult] holds its children and a [stats]
/// computed once at build time. Node transactions are not materialized — the
/// [transactions] extension getter walks the subtree lazily.
///
/// Leaves only ever appear at the deepest grouping level (or as the
/// entire result for an ungrouped query).
///
/// A plain mutable sealed tree (not `freezed`): it is not serialized and
/// nothing relies on value-equality, so immutability would buy us nothing but
/// the awkwardness of rebuilding the tree on every save.
///
/// The tree owns the fold. [add] takes a transaction, routes each of its
/// matching legs down the [groupBy] path, bumps stats at every node, and
/// records the row at the leaf; [remove] is its inverse. `LedgerService.query`
/// builds a result by `add`-ing every transaction into an empty tree, and
/// `LedgerView` maintains its tree by forwarding each save to [remove]/[add] —
/// so the traversal/fold lives in exactly one place.
sealed class QueryResult {
  final GroupKey key;
  Stats stats;

  QueryResult(this.key, this.stats);

  factory QueryResult.leaf({
    required GroupKey key,
    required TransactionSource source,
    required Stats stats,
  }) = LeafResult;

  factory QueryResult.node({
    required GroupKey key,
    required List<QueryResult> children,
    required Stats stats,
  }) = NodeResult;

  /// An empty root for [groupBy]: a [LeafResult] when ungrouped, else a
  /// childless [NodeResult]. [template] sets the zero-state stats and fixes
  /// which [Stat] kinds every bucket tracks.
  factory QueryResult.empty(List<GroupDimension> groupBy, Stats template) =>
      groupBy.isEmpty
          ? LeafResult(
              key: const GroupKey.none(),
              source: const TransactionSource(),
              stats: template,
            )
          : NodeResult(
              key: const GroupKey.none(),
              children: [],
              stats: template,
            );

  /// Folds [tx]'s legs that match [filter] into this tree: bumps stats along
  /// each leg's [groupBy] path (creating buckets from [template] as needed)
  /// and records the row at the destination leaf. The single fold shared by
  /// `LedgerService.query` and `LedgerView`. Call on the root.
  void add(
    Transaction tx,
    LedgerFilter filter,
    List<GroupDimension> groupBy,
    Stats template,
  ) {
    for (final leg in filter.apply(tx)) {
      _fold(leg, tx, groupBy, 0, template: template, stamp: tx);
    }
  }

  /// Undoes a prior [add] of [tx]: re-applies each matching leg with `deleted`
  /// flipped (the [Stat] convention turns that into a subtract) and forgets
  /// the row, then prunes any bucket left empty. Call on the root.
  void remove(
    Transaction tx,
    LedgerFilter filter,
    List<GroupDimension> groupBy,
  ) {
    final reverted = tx.copyWith(deleted: !tx.deleted);
    for (final leg in filter.apply(tx)) {
      _fold(leg, reverted, groupBy, 0, unstamp: tx.id);
    }
    _prune(groupBy, 0);
  }

  /// Folds one [leg] of [tx] along its [groupBy] path from [depth], applying
  /// to every node's stats. On the add pass [template] is non-null so missing
  /// buckets are created and [stamp] records the row at the leaf; on the
  /// remove pass [template] is null (the path pre-exists) and [unstamp]
  /// forgets the row.
  void _fold(
    Leg leg,
    Transaction tx,
    List<GroupDimension> groupBy,
    int depth, {
    Stats? template,
    Transaction? stamp,
    TransactionId? unstamp,
  }) {
    stats = stats.apply(leg, tx);
    final self = this;
    if (depth == groupBy.length) {
      self as LeafResult;
      if (stamp != null) self.source = _stampInto(self.source, stamp);
      if (unstamp != null) self.source = _unstampFrom(self.source, unstamp);
      return;
    }
    self as NodeResult;
    final childKey = groupBy[depth].keyFor(leg, tx);
    var child = self.childFor(childKey);
    if (child == null) {
      if (template == null) return; // removing a path that isn't there
      child = depth + 1 == groupBy.length
          ? LeafResult(
              key: childKey, source: const TransactionSource(), stats: template)
          : NodeResult(key: childKey, children: [], stats: template);
      self.children.add(child);
    }
    child._fold(leg, tx, groupBy, depth + 1,
        template: template, stamp: stamp, unstamp: unstamp);
  }

  /// Drops empty subtrees bottom-up. Returns whether this node is now empty
  /// and its parent should remove it; the root (depth 0) is kept regardless.
  bool _prune(List<GroupDimension> groupBy, int depth) {
    final self = this;
    if (depth == groupBy.length) {
      return (self as LeafResult).source.materialized.isEmpty && depth > 0;
    }
    self as NodeResult;
    self.children.removeWhere((child) => child._prune(groupBy, depth + 1));
    return self.children.isEmpty && depth > 0;
  }
}

class LeafResult extends QueryResult {
  /// The rows behind this bucket. Swapped wholesale as a save adds or removes
  /// a row.
  TransactionSource source;

  LeafResult({required GroupKey key, required this.source, required Stats stats})
      : super(key, stats);
}

class NodeResult extends QueryResult {
  /// One child per distinct group key at the next dimension. New buckets are
  /// appended on [add]; emptied ones removed on [remove].
  final List<QueryResult> children;

  NodeResult(
      {required GroupKey key, required this.children, required Stats stats})
      : super(key, stats);

  /// The child under [key], or null if no leg has routed there yet.
  QueryResult? childFor(GroupKey key) {
    for (final child in children) {
      if (child.key == key) return child;
    }
    return null;
  }
}

/// Unified accessors over the sealed [QueryResult] tree.
extension QueryResultOps on QueryResult {
  /// Transactions in this subtree, deduplicated by id. On a [LeafResult]
  /// returns the [TransactionSource]'s materialized rows; on a [NodeResult]
  /// returns a lazy iterator that walks the children and dedups by id.
  Iterable<Transaction> get transactions => switch (this) {
        LeafResult(source: final s) => s.materialized,
        NodeResult(:final children) =>
          _dedupTransactions(children.expand((c) => c.transactions)),
      };

  /// Children of this node. Empty for a [LeafResult].
  Iterable<QueryResult> get children => switch (this) {
        LeafResult _ => const Iterable<QueryResult>.empty(),
        NodeResult(children: final c) => c,
      };
}

/// A [LeafResult]'s transactions. For now just the materialized rows behind
/// the bucket; Phase 1.8 PR C will add an unhydrated checkpoint base (rows
/// folded in before a disk-restored view's watermark) alongside these, so a
/// leaf can stay lazy until a drill-down asks for its rows.
class TransactionSource {
  final List<Transaction> materialized;

  const TransactionSource({this.materialized = const []});
}

TransactionSource _stampInto(TransactionSource source, Transaction row) =>
    TransactionSource(materialized: [
      for (final t in source.materialized)
        if (t.id != row.id) t,
      row,
    ]);

TransactionSource _unstampFrom(TransactionSource source, TransactionId id) =>
    TransactionSource(materialized: [
      for (final t in source.materialized)
        if (t.id != id) t,
    ]);

Iterable<Transaction> _dedupTransactions(Iterable<Transaction> txs) sync* {
  final seen = <TransactionId>{};
  for (final t in txs) {
    if (seen.add(t.id)) yield t;
  }
}
