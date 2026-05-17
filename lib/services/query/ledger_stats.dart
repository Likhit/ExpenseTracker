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

/// Tree returned by `LedgerService.query`. Always rooted at a node with
/// `GroupKey.none()` (unless there's no grouping, in which case the root
/// is a single leaf with `GroupKey.none()`).
///
/// A [LeafResult] holds the bucket's transactions and stats directly.
/// A [NodeResult] holds only children; its [stats] and [transactions]
/// are derived from the subtree on access. Leaves only ever appear at
/// the deepest grouping level (or as the entire result for an ungrouped
/// query).
@freezed
sealed class QueryResult with _$QueryResult {
  const QueryResult._();

  const factory QueryResult.leaf({
    required GroupKey key,
    required List<Transaction> transactions,
    required Stats stats,
  }) = LeafResult;

  const factory QueryResult.node({
    required GroupKey key,
    required List<QueryResult> children,
  }) = NodeResult;

  /// Stats over this subtree. On a [LeafResult] returns the stored
  /// stats; on a [NodeResult] sums each child's stats.
  Stats get stats => switch (this) {
        LeafResult(stats: final s) => s,
        NodeResult(:final children) =>
          _combineStats(children.map((c) => c.stats)),
      };

  /// Matching transactions in this subtree, deduplicated by id.
  /// Stored on a [LeafResult]; on a [NodeResult] computed as the
  /// dedup-union of every child's transactions.
  List<Transaction> get transactions => switch (this) {
        LeafResult(transactions: final t) => t,
        NodeResult(:final children) =>
          _dedupTransactions(children.expand((c) => c.transactions)),
      };

  /// Children of this node. Empty for a [LeafResult].
  List<QueryResult> get children => switch (this) {
        LeafResult _ => const [],
        NodeResult(children: final c) => c,
      };
}

Stats _combineStats(Iterable<Stats> all) {
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

List<Transaction> _dedupTransactions(Iterable<Transaction> txs) {
  final seen = <TransactionId>{};
  final result = <Transaction>[];
  for (final t in txs) {
    if (seen.add(t.id)) result.add(t);
  }
  return result;
}
