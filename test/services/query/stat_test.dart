import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';
import 'package:expense_tracker/services/query/stat.dart';

void main() {
  final now = DateTime.utc(2026, 4, 19);

  Decimal d(String s) => Decimal.parse(s);

  Leg leg({String currency = 'USD', String amount = '10'}) => Leg(
        accountId: const AccountId('chase'),
        amount: d(amount),
        currencyCode: CurrencyCode(currency),
      );

  Transaction tx({bool deleted = false}) => Transaction(
        id: const TransactionId('tx-1'),
        date: now,
        description: 'x',
        type: TransactionType.expense,
        legs: const [],
        createdAt: now,
        deleted: deleted,
      );

  group('CountStat', () {
    test('apply on active tx increments', () {
      final s = CountStat.empty.apply(leg(), tx());
      expect(s.value, 1);
    });

    test('apply on deleted tx decrements (revert convention)', () {
      final s = CountStat(value: 5).apply(leg(), tx(deleted: true));
      expect(s.value, 4);
    });

    test('apply-then-revert returns to start', () {
      final s = CountStat.empty
          .apply(leg(), tx())
          .apply(leg(), tx(deleted: true));
      expect(s.value, 0);
    });

    test('combine sums', () {
      final a = CountStat(value: 3);
      final b = CountStat(value: 4);
      expect(a.combine(b).value, 7);
    });
  });

  group('SumByCurrencyStat', () {
    test('apply on active tx adds the signed amount', () {
      final s = SumByCurrencyStat.empty.apply(leg(amount: '50'), tx());
      expect(s.value, {const CurrencyCode('USD'): d('50')});
    });

    test('apply on deleted tx subtracts the signed amount', () {
      final s = SumByCurrencyStat(value: {const CurrencyCode('USD'): d('100')})
          .apply(leg(amount: '50'), tx(deleted: true));
      expect(s.value, {const CurrencyCode('USD'): d('50')});
    });

    test('apply-then-revert returns to start', () {
      final s = SumByCurrencyStat.empty
          .apply(leg(amount: '50'), tx())
          .apply(leg(amount: '50'), tx(deleted: true));
      expect(s.value, {const CurrencyCode('USD'): d('0')});
    });

    test('combine merges and sums per currency', () {
      final a = SumByCurrencyStat(value: {
        const CurrencyCode('USD'): d('100'),
        const CurrencyCode('EUR'): d('20'),
      });
      final b = SumByCurrencyStat(value: {
        const CurrencyCode('USD'): d('30'),
        const CurrencyCode('AAPL'): d('5'),
      });
      expect(a.combine(b).value, {
        const CurrencyCode('USD'): d('130'),
        const CurrencyCode('EUR'): d('20'),
        const CurrencyCode('AAPL'): d('5'),
      });
    });
  });

  group('Stats container', () {
    test('defaults tracks count and sumByCurrency', () {
      final s = Stats.defaults();
      expect(s.get<CountStat>(), isNotNull);
      expect(s.get<SumByCurrencyStat>(), isNotNull);
      expect(s.count, 0);
      expect(s.sumByCurrency, isEmpty);
    });

    test('apply folds each contained stat', () {
      final s = Stats.defaults()
          .apply(leg(amount: '50'), tx())
          .apply(leg(amount: '20'), tx());
      expect(s.count, 2);
      expect(s.sumByCurrency, {const CurrencyCode('USD'): d('70')});
    });

    test('combine merges kind-by-kind', () {
      final a = Stats.defaults().apply(leg(amount: '10'), tx());
      final b = Stats.defaults().apply(leg(amount: '20'), tx());
      final c = a.combine(b);
      expect(c.count, 2);
      expect(c.sumByCurrency, {const CurrencyCode('USD'): d('30')});
    });

    test('combine rejects different shapes', () {
      final a = Stats.of(const [CountStat.empty]);
      final b = Stats.of(const [SumByCurrencyStat.empty]);
      expect(() => a.combine(b), throwsStateError);
    });

    test('custom template tracks only the requested stats', () {
      final s = Stats.of(const [CountStat.empty])
          .apply(leg(amount: '50'), tx());
      expect(s.count, 1);
      expect(s.get<SumByCurrencyStat>(), isNull);
      expect(s.sumByCurrency, isEmpty); // convenience getter returns const {}
    });

    test('equality compares kind-by-kind', () {
      final a = Stats.defaults().apply(leg(amount: '5'), tx());
      final b = Stats.defaults().apply(leg(amount: '5'), tx());
      expect(a, b);
    });
  });
}
