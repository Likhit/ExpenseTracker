import 'package:decimal/decimal.dart';

import '../../models/ids.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';

/// One point on a time series: a bucket start plus its per-currency amounts.
///
/// For [timeSeries] the amounts are the bucket's own net flow; for
/// [cumulativeSeries] they are the running total up to and including the bucket.
class TimePoint {
  final DateTime bucketStart;
  final Map<CurrencyCode, Decimal> byCurrency;

  const TimePoint(this.bucketStart, this.byCurrency);

  @override
  bool operator ==(Object other) =>
      other is TimePoint &&
      other.bucketStart == bucketStart &&
      _mapEquals(other.byCurrency, byCurrency);

  @override
  int get hashCode => Object.hash(
      bucketStart,
      Object.hashAllUnordered(
          byCurrency.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => 'TimePoint($bucketStart, $byCurrency)';
}

/// The per-bucket net flow of a query grouped with [GroupDimension.byTime] as
/// its top dimension, in ascending bucket order.
///
/// Reads each time child's rolled-up `stats.sumByCurrency` (the sum of every
/// leg under that bucket). Non-time children (e.g. [GroupKey.none] for legs
/// without the grouping field) are ignored, as is an ungrouped [LeafResult].
List<TimePoint> timeSeries(QueryResult result) {
  final points = <TimePoint>[
    for (final child in result.children)
      if (child.key case TimeKey(:final bucketStart))
        TimePoint(bucketStart, Map.of(child.stats.sumByCurrency)),
  ]..sort((a, b) => a.bucketStart.compareTo(b.bucketStart));
  return points;
}

/// The running cumulative total of [timeSeries] — each point carries the sum of
/// its own bucket plus every earlier bucket, per currency.
///
/// This is what a net-worth trend needs: `byTime` buckets flows *per period*,
/// but net worth is the *accumulated* balance over time. Feed a query filtered
/// to the balance-bearing accounts (see `netWorthFilter` in `report_presets`),
/// grouped by `[byTime(bucket)]`.
List<TimePoint> cumulativeSeries(QueryResult result) {
  final running = <CurrencyCode, Decimal>{};
  final out = <TimePoint>[];
  for (final point in timeSeries(result)) {
    point.byCurrency.forEach((ccy, amount) {
      running.update(ccy, (prev) => prev + amount, ifAbsent: () => amount);
    });
    out.add(TimePoint(point.bucketStart, Map.of(running)));
  }
  return out;
}

bool _mapEquals(Map<CurrencyCode, Decimal> a, Map<CurrencyCode, Decimal> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
