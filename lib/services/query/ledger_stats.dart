import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/transaction.dart';
import 'ledger_group.dart';

part 'ledger_stats.freezed.dart';

/// Aggregates over a set of legs.
///
/// [count] is the number of legs (not transactions) contributing to this
/// bucket. [sumByCurrency] sums each leg's signed amount by its currency.
@freezed
abstract class Stats with _$Stats {
  const factory Stats({
    @Default(0) int count,
    @Default({}) Map<CurrencyCode, Decimal> sumByCurrency,
  }) = _Stats;
}

/// Node in the result tree.
///
/// The root of every query result uses [GroupKey.none] and aggregates
/// every matching leg. Children — one level per [GroupDimension] passed
/// to `query` — partition the same legs along that dimension.
@freezed
abstract class GroupedStats with _$GroupedStats {
  const factory GroupedStats({
    required GroupKey key,
    required Stats stats,
    @Default([]) List<GroupedStats> children,
  }) = _GroupedStats;
}

/// Returned by `LedgerService.query`.
@freezed
abstract class QueryResult with _$QueryResult {
  const factory QueryResult({
    required List<Transaction> transactions,
    required GroupedStats stats,
  }) = _QueryResult;
}
