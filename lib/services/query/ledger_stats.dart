import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_group.dart';
import 'stat.dart';
import 'transaction_source.dart';

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

/// Tree returned by `LedgerService.query` and maintained by `LedgerView`.
///
/// A [LeafResult] holds its bucket's stats plus a [TransactionSource] — the
/// rows behind the bucket, which may be fully materialized (one-shot query,
/// in-memory view) or partly behind an unhydrated checkpoint (a view restored
/// from disk, PR C). A [NodeResult] holds its children and a [stats] computed
/// once at build time. Node transactions are not materialized — the
/// [transactions] extension getter walks the subtree lazily.
///
/// Leaves only ever appear at the deepest grouping level (or as the
/// entire result for an ungrouped query).
@freezed
sealed class QueryResult with _$QueryResult {
  const factory QueryResult.leaf({
    required GroupKey key,
    required TransactionSource source,
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
  /// Synchronously-available transactions in this subtree, deduplicated by
  /// id.
  ///
  /// On a [LeafResult] returns the [TransactionSource]'s materialized rows.
  /// NOTE: a leaf restored from disk may hold an unhydrated [Checkpoint], in
  /// which case this returns only the overlay — full resolution (PR C) is
  /// async via the ledger. On a [NodeResult] returns a lazy iterator that
  /// walks the children and dedups by id.
  Iterable<Transaction> get transactions => switch (this) {
        LeafResult(source: final s) => s.recentRows,
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
