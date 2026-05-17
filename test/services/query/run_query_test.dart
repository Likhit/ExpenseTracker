import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/query/ledger_filter.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';
import 'package:expense_tracker/services/query/run_query.dart';

void main() {
  // A small fixture journal that exercises every dimension.
  //
  //   tx-1 (2026-04-19, expense)  Chase --$50 USD->  Food::Groceries
  //   tx-2 (2026-04-01, income )  Salary -$1000 USD-> Chase
  //   tx-3 (2026-05-15, transfer) Chase --$2000 USD-> Fidelity +10 AAPL
  //   tx-4 (2026-05-01, expense)  Chase --€5 EUR->   Food::Snacks::Coffee
  //   tx-5 (2026-05-10, deleted expense) Chase --$100 USD-> Food::Groceries
  final now = DateTime.utc(2026, 6, 1);

  Decimal d(String s) => Decimal.parse(s);

  final txs = [
    Transaction(
      id: const TransactionId('tx-1'),
      date: DateTime.utc(2026, 4, 19),
      description: 'Groceries',
      type: TransactionType.expense,
      legs: [
        Leg(
          accountId: const AccountId('chase'),
          amount: d('-50'),
          currencyCode: const CurrencyCode('USD'),
        ),
        Leg(
          accountId: const AccountId('exp-food'),
          amount: d('50'),
          currencyCode: const CurrencyCode('USD'),
          categoryPath: const CategoryPath('Food::Groceries'),
        ),
      ],
      createdAt: now,
    ),
    Transaction(
      id: const TransactionId('tx-2'),
      date: DateTime.utc(2026, 4, 1),
      description: 'Salary',
      type: TransactionType.income,
      legs: [
        Leg(
          accountId: const AccountId('income-salary'),
          amount: d('-1000'),
          currencyCode: const CurrencyCode('USD'),
          categoryPath: const CategoryPath('Salary'),
        ),
        Leg(
          accountId: const AccountId('chase'),
          amount: d('1000'),
          currencyCode: const CurrencyCode('USD'),
        ),
      ],
      createdAt: now,
    ),
    Transaction(
      id: const TransactionId('tx-3'),
      date: DateTime.utc(2026, 5, 15),
      description: 'Stock buy',
      type: TransactionType.transfer,
      legs: [
        Leg(
          accountId: const AccountId('chase'),
          amount: d('-2000'),
          currencyCode: const CurrencyCode('USD'),
        ),
        Leg(
          accountId: const AccountId('fidelity'),
          amount: d('10'),
          currencyCode: const CurrencyCode('AAPL'),
        ),
      ],
      metadata: const {
        'exchangeRate': {'from': 'USD', 'to': 'AAPL', 'rate': '0.005'},
      },
      createdAt: now,
    ),
    Transaction(
      id: const TransactionId('tx-4'),
      date: DateTime.utc(2026, 5, 1),
      description: 'Coffee',
      type: TransactionType.expense,
      legs: [
        Leg(
          accountId: const AccountId('chase'),
          amount: d('-5'),
          currencyCode: const CurrencyCode('EUR'),
        ),
        Leg(
          accountId: const AccountId('exp-food'),
          amount: d('5'),
          currencyCode: const CurrencyCode('EUR'),
          categoryPath: const CategoryPath('Food::Snacks::Coffee'),
        ),
      ],
      createdAt: now,
    ),
    Transaction(
      id: const TransactionId('tx-5'),
      date: DateTime.utc(2026, 5, 10),
      description: 'Cancelled',
      type: TransactionType.expense,
      legs: [
        Leg(
          accountId: const AccountId('chase'),
          amount: d('-100'),
          currencyCode: const CurrencyCode('USD'),
        ),
        Leg(
          accountId: const AccountId('exp-food'),
          amount: d('100'),
          currencyCode: const CurrencyCode('USD'),
          categoryPath: const CategoryPath('Food::Groceries'),
        ),
      ],
      createdAt: now,
      deleted: true,
    ),
  ];

  group('runQuery — filtering', () {
    test('empty filter matches every leg of every non-deleted transaction',
        () {
      final result = runQuery(txs, const LedgerFilter());

      // 4 non-deleted txns x 2 legs each = 8 legs.
      expect(result.transactions, hasLength(4));
      expect(result.stats.stats.count, 8);
      // USD: -50 + 50 - 1000 + 1000 - 2000 = -2000
      // EUR: -5 + 5 = 0
      // AAPL: 10
      expect(result.stats.stats.sumByCurrency[const CurrencyCode('USD')],
          d('-2000'));
      expect(
          result.stats.stats.sumByCurrency[const CurrencyCode('EUR')], d('0'));
      expect(result.stats.stats.sumByCurrency[const CurrencyCode('AAPL')],
          d('10'));
    });

    test('includeDeleted brings back the cancelled transaction', () {
      final result =
          runQuery(txs, const LedgerFilter(includeDeleted: true));
      expect(result.transactions, hasLength(5));
      expect(result.stats.stats.count, 10);
    });

    test('filter by accounts keeps only legs touching those accounts', () {
      final result = runQuery(
        txs,
        const LedgerFilter(accounts: {AccountId('chase')}),
      );
      // Chase appears in tx-1, tx-2, tx-3, tx-4 (one leg each).
      expect(result.transactions, hasLength(4));
      expect(result.stats.stats.count, 4);
      expect(result.stats.stats.sumByCurrency[const CurrencyCode('USD')],
          d('-1050')); // -50 + 1000 - 2000
      expect(
          result.stats.stats.sumByCurrency[const CurrencyCode('EUR')], d('-5'));
    });

    test('filter by currency excludes other-currency legs from sums', () {
      final result = runQuery(
        txs,
        const LedgerFilter(currencies: {CurrencyCode('EUR')}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.stats.stats.sumByCurrency, {
        const CurrencyCode('EUR'): d('0'),
      });
    });

    test('filter by category is segment-aware: Food matches Food::Snacks', () {
      final result = runQuery(
        txs,
        const LedgerFilter(categories: {CategoryPath('Food')}),
      );
      // Matches the Food::Groceries leg (tx-1) and Food::Snacks::Coffee leg (tx-4).
      expect(result.transactions, hasLength(2));
      expect(result.stats.stats.count, 2);
    });

    test('filter by category does not match an unrelated prefix string', () {
      final result = runQuery(
        txs,
        const LedgerFilter(categories: {CategoryPath('Fo')}),
      );
      expect(result.transactions, isEmpty);
      expect(result.stats.stats.count, 0);
    });

    test('filter by category exact match still works', () {
      final result = runQuery(
        txs,
        const LedgerFilter(categories: {CategoryPath('Food::Groceries')}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.transactions.first.id, const TransactionId('tx-1'));
    });

    test('filter by date range', () {
      final result = runQuery(
        txs,
        LedgerFilter(from: DateTime.utc(2026, 5, 1)),
      );
      // tx-3 (5/15) and tx-4 (5/1).
      expect(result.transactions.map((t) => t.id), {
        const TransactionId('tx-3'),
        const TransactionId('tx-4'),
      });
    });

    test('filter by transaction types', () {
      final result = runQuery(
        txs,
        const LedgerFilter(types: {TransactionType.income}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.transactions.first.id, const TransactionId('tx-2'));
    });
  });

  group('runQuery — grouping', () {
    test('group by account', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [GroupDimension.byAccount()],
      );
      final byAccount = {
        for (final c in result.stats.children) (c.key as AccountKey).id: c
      };
      expect(byAccount.keys, containsAll({
        const AccountId('chase'),
        const AccountId('exp-food'),
        const AccountId('income-salary'),
        const AccountId('fidelity'),
      }));
      // Chase: USD -50 + 1000 - 2000 = -1050; EUR -5
      expect(byAccount[const AccountId('chase')]!.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-1050'), const CurrencyCode('EUR'): d('-5')});
    });

    test('group by currency', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCurrency()],
      );
      final byCcy = {
        for (final c in result.stats.children) (c.key as CurrencyKey).code: c
      };
      expect(byCcy[const CurrencyCode('USD')]!.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-2000')});
      expect(byCcy[const CurrencyCode('AAPL')]!.stats.sumByCurrency,
          {const CurrencyCode('AAPL'): d('10')});
    });

    test('group by category at depth 1', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCategory()],
      );
      final keys = result.stats.children.map((c) => c.key).toSet();
      expect(keys, contains(const GroupKey.category(CategoryPath('Food'))));
      expect(keys, contains(const GroupKey.category(CategoryPath('Salary'))));
      // Legs without category fall under none().
      expect(keys, contains(const GroupKey.none()));
    });

    test('group by category at depth 2 truncates deeper paths', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCategory(depth: 2)],
      );
      final keys = result.stats.children.map((c) => c.key).toSet();
      // Food::Groceries stays; Food::Snacks::Coffee truncates to Food::Snacks.
      expect(keys, contains(
          const GroupKey.category(CategoryPath('Food::Groceries'))));
      expect(
          keys, contains(const GroupKey.category(CategoryPath('Food::Snacks'))));
    });

    test('group by time (month)', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [GroupDimension.byTime(TimeBucket.month)],
      );
      final keys = result.stats.children.map((c) => (c.key as TimeKey).bucketStart).toSet();
      expect(keys, {DateTime.utc(2026, 4, 1), DateTime.utc(2026, 5, 1)});
    });

    test('compose: group by account then currency', () {
      final result = runQuery(
        txs,
        const LedgerFilter(),
        groupBy: const [
          GroupDimension.byAccount(),
          GroupDimension.byCurrency(),
        ],
      );
      final chase = result.stats.children
          .firstWhere((c) => (c.key as AccountKey).id == const AccountId('chase'));
      // Chase has USD and EUR sub-buckets.
      final ccyKeys =
          chase.children.map((c) => (c.key as CurrencyKey).code).toSet();
      expect(ccyKeys, {const CurrencyCode('USD'), const CurrencyCode('EUR')});
      final usdNode = chase.children
          .firstWhere((c) => (c.key as CurrencyKey).code == const CurrencyCode('USD'));
      expect(usdNode.stats.sumByCurrency[const CurrencyCode('USD')], d('-1050'));
    });

    test('empty input yields empty result', () {
      final result = runQuery([], const LedgerFilter());
      expect(result.transactions, isEmpty);
      expect(result.stats.children, isEmpty);
      expect(result.stats.stats.count, 0);
    });
  });
}
