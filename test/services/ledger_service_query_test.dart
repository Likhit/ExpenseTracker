import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/query/ledger_filter.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';

void main() {
  // Fixture journal exercising every query dimension:
  //   tx-1 (2026-04-19, expense)  Chase --$50 USD->  Food::Groceries
  //   tx-2 (2026-04-01, income )  Salary -$1000 USD-> Chase
  //   tx-3 (2026-05-15, transfer) Chase --$2000 USD-> Fidelity +10 AAPL
  //   tx-4 (2026-05-01, expense)  Chase --€5 EUR->   Food::Snacks::Coffee
  //   tx-5 (2026-05-10, deleted expense) Chase --$100 USD-> Food::Groceries
  //
  // Note: today every leg requires an accountId, so the expense/income
  // sides use placeholder accounts of type expense/income (e.g.
  // `expenses-food`, `income-salary`). A planned phase will make
  // accountId optional and let category-only legs act as the balancing
  // side; the fixture will collapse accordingly.
  late Directory tempDir;
  late LedgerService ledger;
  final now = DateTime.utc(2026, 6, 1);

  Decimal d(String s) => Decimal.parse(s);

  List<Transaction> fixtureTransactions() => [
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
              accountId: const AccountId('expenses-food'),
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
              accountId: const AccountId('expenses-food'),
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
              accountId: const AccountId('expenses-food'),
              amount: d('100'),
              currencyCode: const CurrencyCode('USD'),
              categoryPath: const CategoryPath('Food::Groceries'),
            ),
          ],
          createdAt: now,
          deleted: true,
        ),
      ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ledger_query_test_');
    ledger = LedgerService(
      accountsPath: '${tempDir.path}/accounts.jsonl',
      categoriesPath: '${tempDir.path}/categories.jsonl',
      currenciesPath: '${tempDir.path}/currencies.jsonl',
      transactionsPath: '${tempDir.path}/transactions.jsonl',
    );
    for (final tx in fixtureTransactions()) {
      // Bypass validation for tx-5 (cross-currency without rate metadata
      // isn't the case here, but we also want to persist the deleted
      // version directly). Use the raw repo via saveAll for setup speed.
      await ledger.save(tx);
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('query — filtering', () {
    test('empty filter matches every leg of every non-deleted transaction',
        () async {
      final result = await ledger.query(const LedgerFilter());

      expect(result.transactions, hasLength(4));
      expect(result.stats.count, 8);
      expect(result.stats.sumByCurrency[const CurrencyCode('USD')],
          d('-2000'));
      expect(
          result.stats.sumByCurrency[const CurrencyCode('EUR')], d('0'));
      expect(result.stats.sumByCurrency[const CurrencyCode('AAPL')],
          d('10'));
    });

    test('includeDeleted brings back the cancelled transaction', () async {
      final result =
          await ledger.query(const LedgerFilter(includeDeleted: true));
      expect(result.transactions, hasLength(5));
      expect(result.stats.count, 10);
    });

    test('filter by accounts keeps only legs touching those accounts',
        () async {
      final result = await ledger.query(
        const LedgerFilter(accounts: {AccountId('chase')}),
      );
      expect(result.transactions, hasLength(4));
      expect(result.stats.count, 4);
      expect(result.stats.sumByCurrency[const CurrencyCode('USD')],
          d('-1050'));
      expect(
          result.stats.sumByCurrency[const CurrencyCode('EUR')], d('-5'));
    });

    test('filter by currency excludes other-currency legs from sums',
        () async {
      final result = await ledger.query(
        const LedgerFilter(currencies: {CurrencyCode('EUR')}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.stats.sumByCurrency, {
        const CurrencyCode('EUR'): d('0'),
      });
    });

    test('filter by category is segment-aware: Food matches Food::Snacks',
        () async {
      final result = await ledger.query(
        const LedgerFilter(categories: {CategoryPath('Food')}),
      );
      // Matches the Food::Groceries leg (+$50) and the
      // Food::Snacks::Coffee leg (+€5).
      expect(result.transactions, hasLength(2));
      expect(result.stats.count, 2);
      expect(result.stats.sumByCurrency, {
        const CurrencyCode('USD'): d('50'),
        const CurrencyCode('EUR'): d('5'),
      });
    });

    test('filter by category does not match an unrelated prefix string',
        () async {
      final result = await ledger.query(
        const LedgerFilter(categories: {CategoryPath('Fo')}),
      );
      expect(result.transactions, isEmpty);
      expect(result.stats.count, 0);
    });

    test('filter by category exact match still works', () async {
      final result = await ledger.query(
        const LedgerFilter(categories: {CategoryPath('Food::Groceries')}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.transactions.first.id, const TransactionId('tx-1'));
      expect(result.stats.sumByCurrency, {
        const CurrencyCode('USD'): d('50'),
      });
    });

    test('filter by date range', () async {
      final result = await ledger.query(
        LedgerFilter(from: DateTime.utc(2026, 5, 1)),
      );
      expect(result.transactions.map((t) => t.id), {
        const TransactionId('tx-3'),
        const TransactionId('tx-4'),
      });
    });

    test('filter by transaction type: income', () async {
      final result = await ledger.query(
        const LedgerFilter(types: {TransactionType.income}),
      );
      expect(result.transactions, hasLength(1));
      expect(result.transactions.first.id, const TransactionId('tx-2'));
      // Income tx is same-currency-balanced (salary -$1000 + Chase +$1000).
      expect(result.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('0')});
    });

    test('filter by transaction type: expense', () async {
      final result = await ledger.query(
        const LedgerFilter(types: {TransactionType.expense}),
      );
      // tx-1 (USD groceries) and tx-4 (EUR coffee). tx-5 is deleted.
      expect(result.transactions.map((t) => t.id), {
        const TransactionId('tx-1'),
        const TransactionId('tx-4'),
      });
      expect(result.stats.sumByCurrency, {
        const CurrencyCode('USD'): d('0'),
        const CurrencyCode('EUR'): d('0'),
      });
    });
  });

  group('query — grouping', () {
    test('group by account', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [GroupDimension.byAccount()],
      );
      final byAccount = {
        for (final c in result.children) (c.key as AccountKey).id: c,
      };
      expect(
          byAccount.keys,
          containsAll({
            const AccountId('chase'),
            const AccountId('expenses-food'),
            const AccountId('income-salary'),
            const AccountId('fidelity'),
          }));
      expect(byAccount[const AccountId('chase')]!.stats.sumByCurrency, {
        const CurrencyCode('USD'): d('-1050'),
        const CurrencyCode('EUR'): d('-5'),
      });
    });

    test('group by currency', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCurrency()],
      );
      final byCcy = {
        for (final c in result.children) (c.key as CurrencyKey).code: c,
      };
      expect(byCcy[const CurrencyCode('USD')]!.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-2000')});
      expect(byCcy[const CurrencyCode('AAPL')]!.stats.sumByCurrency,
          {const CurrencyCode('AAPL'): d('10')});
    });

    test('group by category at depth 1', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCategory()],
      );
      final keys = result.children.map((c) => c.key).toSet();
      expect(keys, contains(const GroupKey.category(CategoryPath('Food'))));
      expect(keys, contains(const GroupKey.category(CategoryPath('Salary'))));
      expect(keys, contains(const GroupKey.none()));
    });

    test('group by category at depth 2 truncates deeper paths', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [GroupDimension.byCategory(depth: 2)],
      );
      final keys = result.children.map((c) => c.key).toSet();
      expect(keys,
          contains(const GroupKey.category(CategoryPath('Food::Groceries'))));
      expect(keys,
          contains(const GroupKey.category(CategoryPath('Food::Snacks'))));
    });

    test('group by time (month)', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [GroupDimension.byTime(TimeBucket.month)],
      );
      final keys = result.children
          .map((c) => (c.key as TimeKey).bucketStart)
          .toSet();
      expect(keys, {DateTime.utc(2026, 4, 1), DateTime.utc(2026, 5, 1)});
    });

    test('intermediate node derives stats and transactions from children',
        () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [
          GroupDimension.byAccount(),
          GroupDimension.byCurrency(),
        ],
      );
      final chase = result.children.firstWhere(
          (c) => (c.key as AccountKey).id == const AccountId('chase'));
      // Chase appears as a leg in tx-1, tx-2, tx-3, tx-4 — deduped.
      expect(chase.transactions.map((t) => t.id).toSet(), {
        const TransactionId('tx-1'),
        const TransactionId('tx-2'),
        const TransactionId('tx-3'),
        const TransactionId('tx-4'),
      });
      // Chase total = sum of USD and EUR leaves.
      expect(chase.stats.count, 4);
      expect(chase.stats.sumByCurrency, {
        const CurrencyCode('USD'): d('-1050'),
        const CurrencyCode('EUR'): d('-5'),
      });
    });

    test('compose: group by account then currency', () async {
      final result = await ledger.query(
        const LedgerFilter(),
        groupBy: const [
          GroupDimension.byAccount(),
          GroupDimension.byCurrency(),
        ],
      );
      final chase = result.children.firstWhere(
          (c) => (c.key as AccountKey).id == const AccountId('chase'));
      final ccyKeys =
          chase.children.map((c) => (c.key as CurrencyKey).code).toSet();
      expect(ccyKeys, {const CurrencyCode('USD'), const CurrencyCode('EUR')});
      final usdNode = chase.children.firstWhere(
          (c) => (c.key as CurrencyKey).code == const CurrencyCode('USD'));
      expect(usdNode.stats.sumByCurrency[const CurrencyCode('USD')],
          d('-1050'));
    });
  });

  test('empty journal yields empty result', () async {
    final freshDir =
        await Directory.systemTemp.createTemp('ledger_query_empty_');
    addTearDown(() async {
      if (await freshDir.exists()) await freshDir.delete(recursive: true);
    });
    final empty = LedgerService(
      accountsPath: '${freshDir.path}/accounts.jsonl',
      categoriesPath: '${freshDir.path}/categories.jsonl',
      currenciesPath: '${freshDir.path}/currencies.jsonl',
      transactionsPath: '${freshDir.path}/transactions.jsonl',
    );
    final result = await empty.query(const LedgerFilter());
    expect(result.transactions, isEmpty);
    expect(result.children, isEmpty);
    expect(result.stats.count, 0);
  });
}
