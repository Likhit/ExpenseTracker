import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_group.dart';
import 'stat.dart';

part 'ledger_stats.freezed.dart';

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

/// Tree returned by `LedgerService.query`.
///
/// A [LeafResult] holds its bucket's transactions and stats directly.
/// A [NodeResult] holds only its children and a pre-computed [stats]
/// (rolled up once at build time, cached for the life of the result).
/// Node transactions are not materialized — the [transactions] extension
/// getter returns a lazy iterator that walks the subtree.
///
/// Leaves only ever appear at the deepest grouping level (or as the
/// entire result for an ungrouped query).
@freezed
sealed class QueryResult with _$QueryResult {
  const factory QueryResult.leaf({
    required GroupKey key,
    required Iterable<Transaction> transactions,
    required Stats stats,
  }) = LeafResult;

  const factory QueryResult.node({
    required GroupKey key,
    required Iterable<QueryResult> children,
    required Stats stats,
  }) = NodeResult;
}

/// Unified accessors over the sealed [QueryResult] tree.
extension QueryResultOps on QueryResult {
  /// Matching transactions in this subtree, deduplicated by id.
  ///
  /// On a [LeafResult] returns the stored iterable directly. On a
  /// [NodeResult] returns a lazy iterator that walks the children and
  /// dedups by id — nothing is materialized until the caller iterates.
  Iterable<Transaction> get transactions => switch (this) {
        LeafResult(transactions: final t) => t,
        NodeResult(:final children) =>
          _dedupTransactions(children.expand((c) => c.transactions)),
      };

  /// Children of this node. Empty for a [LeafResult].
  Iterable<QueryResult> get children => switch (this) {
        LeafResult _ => const Iterable<QueryResult>.empty(),
        NodeResult(children: final c) => c,
      };
}

/// Folds every [Stats] in [all] into one via [Stats.combine]. Returns a
/// default-template [Stats] when [all] is empty (the identity).
Stats combineStats(Iterable<Stats> all) {
  Stats? combined;
  for (final s in all) {
    combined = combined == null ? s : combined.combine(s);
  }
  return combined ?? Stats.defaults();
}

Iterable<Transaction> _dedupTransactions(Iterable<Transaction> txs) sync* {
  final seen = <TransactionId>{};
  for (final t in txs) {
    if (seen.add(t.id)) yield t;
  }
}
