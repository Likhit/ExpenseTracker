import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/transaction.dart';
import 'ledger_group.dart';

part 'ledger_stats.freezed.dart';

/// Aggregates over a set of legs. [count] is the number of legs (not
/// transactions); [sumByCurrency] sums each leg's signed amount by its
/// currency.
@freezed
abstract class Stats with _$Stats {
  const factory Stats({
    @Default(0) int count,
    @Default({}) Map<CurrencyCode, Decimal> sumByCurrency,
  }) = _Stats;
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

/// Sums each child's [Stats] into one. Used by `LedgerService._buildTree`
/// when constructing a [NodeResult] so the rollup happens once.
Stats combineStats(Iterable<Stats> all) {
  var count = 0;
  final sums = <CurrencyCode, Decimal>{};
  for (final s in all) {
    count += s.count;
    s.sumByCurrency.forEach((ccy, amount) {
      sums.update(ccy, (existing) => existing + amount, ifAbsent: () => amount);
    });
  }
  return Stats(count: count, sumByCurrency: sums);
}

Iterable<Transaction> _dedupTransactions(Iterable<Transaction> txs) sync* {
  final seen = <TransactionId>{};
  for (final t in txs) {
    if (seen.add(t.id)) yield t;
  }
}
