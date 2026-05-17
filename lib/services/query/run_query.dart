import 'package:decimal/decimal.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';

/// Pure function that runs a filter+group query over an in-memory list
/// of transactions. Kept separate from `LedgerService` so the algorithm
/// can be exercised against fixture journals without touching disk.
QueryResult runQuery(
  List<Transaction> transactions,
  LedgerFilter filter, {
  List<GroupDimension> groupBy = const [],
}) {
  final matchedTxs = <Transaction>[];
  final matchedLegs = <_MatchedLeg>[];

  for (final tx in transactions) {
    final legs = filter.apply(tx);
    if (legs.isEmpty) continue;
    matchedTxs.add(tx);
    for (final leg in legs) {
      matchedLegs.add(_MatchedLeg(leg, tx));
    }
  }

  final stats = GroupedStats(
    key: const GroupKey.none(),
    stats: _statsOf(matchedLegs),
    children: _buildChildren(matchedLegs, groupBy),
  );

  return QueryResult(transactions: matchedTxs, stats: stats);
}

class _MatchedLeg {
  final Leg leg;
  final Transaction tx;
  const _MatchedLeg(this.leg, this.tx);
}

List<GroupedStats> _buildChildren(
  List<_MatchedLeg> legs,
  List<GroupDimension> groupBy,
) {
  if (groupBy.isEmpty || legs.isEmpty) return const [];
  final dim = groupBy.first;
  final rest = groupBy.sublist(1);

  // Insertion-ordered: groups appear in the order their first leg was
  // encountered. Deterministic given the input order.
  final buckets = <GroupKey, List<_MatchedLeg>>{};
  for (final ml in legs) {
    final key = dim.keyFor(ml.leg, ml.tx);
    buckets.putIfAbsent(key, () => <_MatchedLeg>[]).add(ml);
  }

  return [
    for (final entry in buckets.entries)
      GroupedStats(
        key: entry.key,
        stats: _statsOf(entry.value),
        children: _buildChildren(entry.value, rest),
      ),
  ];
}

Stats _statsOf(List<_MatchedLeg> legs) {
  final sums = <CurrencyCode, Decimal>{};
  for (final ml in legs) {
    sums.update(
      ml.leg.currencyCode,
      (existing) => existing + ml.leg.amount,
      ifAbsent: () => ml.leg.amount,
    );
  }
  return Stats(count: legs.length, sumByCurrency: sums);
}
