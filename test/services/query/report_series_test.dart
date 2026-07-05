import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';
import 'package:expense_tracker/services/query/report_series.dart';
import 'package:expense_tracker/services/query/stat.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);
  const usd = CurrencyCode('USD');
  const eur = CurrencyCode('EUR');

  /// Builds a byTime-grouped result: one time child per (bucketStart, sums)
  /// entry, each carrying a SumByCurrencyStat with those sums. Children are
  /// added out of chronological order to prove the helpers sort.
  QueryResult timeGrouped(List<(DateTime, Map<CurrencyCode, Decimal>)> buckets) {
    final children = <QueryResult>[
      for (final (start, sums) in buckets)
        LeafResult(
          key: GroupKey.time(start),
          source: const TransactionSource(),
          stats: Stats.of([SumByCurrencyStat(value: sums)]),
        ),
    ];
    return NodeResult(
      key: const GroupKey.none(),
      children: children,
      stats: Stats.of([const SumByCurrencyStat()]),
    );
  }

  group('timeSeries', () {
    test('returns per-bucket sums in ascending bucket order', () {
      final result = timeGrouped([
        (DateTime.utc(2026, 3, 1), {usd: d('30')}),
        (DateTime.utc(2026, 1, 1), {usd: d('10')}),
        (DateTime.utc(2026, 2, 1), {usd: d('20')}),
      ]);

      final series = timeSeries(result);
      expect(series.map((p) => p.bucketStart), [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ]);
      expect(series.map((p) => p.byCurrency[usd]), [d('10'), d('20'), d('30')]);
    });

    test('ignores non-time children and an ungrouped leaf', () {
      final mixed = NodeResult(
        key: const GroupKey.none(),
        children: [
          LeafResult(
            key: GroupKey.time(DateTime.utc(2026, 1, 1)),
            source: const TransactionSource(),
            stats: Stats.of([SumByCurrencyStat(value: {usd: d('5')})]),
          ),
          // A none-key bucket (e.g. legs missing the grouping field).
          LeafResult(
            key: const GroupKey.none(),
            source: const TransactionSource(),
            stats: Stats.of([SumByCurrencyStat(value: {usd: d('99')})]),
          ),
        ],
        stats: Stats.of([const SumByCurrencyStat()]),
      );
      expect(timeSeries(mixed), hasLength(1));

      final leaf = LeafResult(
        key: const GroupKey.none(),
        source: const TransactionSource(),
        stats: Stats.of([const SumByCurrencyStat()]),
      );
      expect(timeSeries(leaf), isEmpty);
    });
  });

  group('cumulativeSeries', () {
    test('accumulates a running total across buckets, per currency', () {
      final result = timeGrouped([
        (DateTime.utc(2026, 1, 1), {usd: d('100')}),
        (DateTime.utc(2026, 2, 1), {usd: d('50'), eur: d('20')}),
        (DateTime.utc(2026, 3, 1), {usd: d('-30')}),
      ]);

      final series = cumulativeSeries(result);
      expect(series.map((p) => p.byCurrency[usd]).toList(),
          [d('100'), d('150'), d('120')]);
      // EUR only appears from Feb onward; it accumulates from there.
      expect(series[0].byCurrency.containsKey(eur), isFalse);
      expect(series[1].byCurrency[eur], d('20'));
      expect(series[2].byCurrency[eur], d('20'));
    });

    test('empty result yields an empty series', () {
      expect(cumulativeSeries(timeGrouped(const [])), isEmpty);
    });
  });
}
