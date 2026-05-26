import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/query/ledger_filter.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';

void main() {
  late Directory tempDir;
  final now = DateTime.utc(2026, 6, 1);

  Decimal d(String s) => Decimal.parse(s);

  Transaction expense({
    required String id,
    required String amount,
    String currency = 'USD',
    String category = 'Food::Groceries',
    DateTime? date,
    bool deleted = false,
  }) =>
      Transaction(
        id: TransactionId(id),
        date: date ?? now,
        description: 'tx-$id',
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('chase'),
            amount: d('-$amount'),
            currencyCode: CurrencyCode(currency),
            categoryPath: CategoryPath(category),
          ),
          Leg(
            accountId: Account.expenseId,
            amount: d(amount),
            currencyCode: CurrencyCode(currency),
          ),
        ],
        createdAt: now,
        deleted: deleted,
      );

  Future<LedgerService> freshLedger() => LedgerService.create(
        accountsPath: '${tempDir.path}/accounts.jsonl',
        categoriesPath: '${tempDir.path}/categories.jsonl',
        currenciesPath: '${tempDir.path}/currencies.jsonl',
        transactionsPath: '${tempDir.path}/transactions.jsonl',
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ledger_view_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('LedgerView lifecycle', () {
    test('a freshly registered view returns the empty tree', () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'balances', groupBy: const [
        GroupDimension.byAccount(),
        GroupDimension.byCurrency(),
      ]);
      final result = ledger.viewResult('balances')!.result;
      expect(result.children, isEmpty);
      expect(result.stats.count, 0);
    });

    test('unknown view name returns null', () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'balances');
      expect(ledger.viewResult('nope'), isNull);
    });

    test('duplicate view names rejected at registration', () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'dup');
      await expectLater(
        ledger.register(name: 'dup'),
        throwsArgumentError,
      );
    });
  });

  group('LedgerView push updates', () {
    test('first save is reflected in the view', () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'totals');
      await ledger.save(expense(id: 'tx-1', amount: '50'));

      final result = ledger.viewResult('totals')!.result;
      expect(result.transactions, hasLength(1));
      expect(result.stats.count, 2);
      // -50 + 50 (same-currency balanced).
      expect(result.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('0')});
    });

    test('grouped view buckets legs by their group key', () async {
      final ledger = await freshLedger();
      await ledger.register(
        name: 'by-account',
        groupBy: const [GroupDimension.byAccount()],
      );
      await ledger.save(expense(id: 'tx-1', amount: '50'));

      final result = ledger.viewResult('by-account')!.result;
      final byAccount = {
        for (final c in result.children) (c.key as AccountKey).id: c,
      };
      expect(byAccount[const AccountId('chase')]!.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-50')});
      expect(byAccount[Account.expenseId]!.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('50')});
    });

    test('editing a transaction reverts the old version and applies the new',
        () async {
      final ledger = await freshLedger();
      await ledger.register(
        name: 'by-account',
        groupBy: const [GroupDimension.byAccount()],
      );
      await ledger.save(expense(id: 'tx-1', amount: '50'));
      // Edit: bump the amount to $80.
      await ledger.save(expense(id: 'tx-1', amount: '80'));

      final result = ledger.viewResult('by-account')!.result;
      final chase = result.children.firstWhere(
          (c) => (c.key as AccountKey).id == const AccountId('chase'));
      expect(chase.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-80')});
      expect(chase.transactions, hasLength(1));
    });

    test('soft-deleting a transaction drops it from the view', () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'totals');
      final tx = expense(id: 'tx-1', amount: '50');
      await ledger.save(tx);
      await ledger.delete(tx);

      final result = ledger.viewResult('totals')!.result;
      // The default filter excludes deleted, so the view's leaf is empty:
      // stats back to zero, transactions gone.
      expect(result.transactions, isEmpty);
      expect(result.stats.count, 0);
      expect(result.stats.sumByCurrency,
          anyOf(isEmpty, {const CurrencyCode('USD'): d('0')}));
    });

    test('view filter excludes non-matching transactions', () async {
      final ledger = await freshLedger();
      await ledger.register(
        name: 'food-only',
        filter: const LedgerFilter(categories: {CategoryPath('Food')}),
      );
      await ledger.save(expense(
          id: 'tx-1', amount: '50', category: 'Food::Groceries'));
      await ledger.save(
          expense(id: 'tx-2', amount: '10', category: 'Transport::Taxi'));

      final result = ledger.viewResult('food-only')!.result;
      expect(result.transactions.map((t) => t.id),
          {const TransactionId('tx-1')});
      // Only the Chase leg of tx-1 carries the Food category, so the sum is
      // just the Chase outflow.
      expect(result.stats.sumByCurrency,
          {const CurrencyCode('USD'): d('-50')});
    });

    test('multiple views with different filters maintained independently',
        () async {
      final ledger = await freshLedger();
      await ledger.register(
          name: 'food',
          filter: const LedgerFilter(categories: {CategoryPath('Food')}));
      await ledger.register(
          name: 'transport',
          filter: const LedgerFilter(categories: {CategoryPath('Transport')}));
      await ledger.save(expense(
          id: 'tx-1', amount: '50', category: 'Food::Groceries'));
      await ledger.save(
          expense(id: 'tx-2', amount: '20', category: 'Transport::Taxi'));

      expect(ledger.viewResult('food')!.result.transactions.map((t) => t.id),
          {const TransactionId('tx-1')});
      expect(
          ledger.viewResult('transport')!.result.transactions.map((t) => t.id),
          {const TransactionId('tx-2')});
    });
  });

  group('LedgerView seeding & rebuild', () {
    test('register seeds the view from an existing journal', () async {
      final first = await freshLedger();
      await first.save(expense(id: 'tx-1', amount: '50'));
      await first.save(expense(id: 'tx-2', amount: '20'));

      // Reopen with a view registered; registration replays the journal.
      final reopened = await freshLedger();
      await reopened.register(name: 'totals');
      final result = reopened.viewResult('totals')!.result;
      expect(result.transactions, hasLength(2));
      // 4 legs total (2 per tx); same-currency balanced.
      expect(result.stats.count, 4);
    });

    test('rebuildViews wipes and re-seeds from current journal state',
        () async {
      final ledger = await freshLedger();
      await ledger.register(name: 'totals');
      await ledger.save(expense(id: 'tx-1', amount: '50'));
      expect(ledger.viewResult('totals')!.result.transactions, hasLength(1));

      await ledger.rebuildViews();
      // After rebuild the state matches the journal as it stands now.
      expect(ledger.viewResult('totals')!.result.transactions, hasLength(1));
      expect(ledger.viewResult('totals')!.result.stats.count, 2);
    });
  });

  group('LedgerView parity with query()', () {
    test('view matches one-shot query for the same filter/groupBy', () async {
      final ledger = await freshLedger();
      await ledger.register(
        name: 'by-account-currency',
        groupBy: const [
          GroupDimension.byAccount(),
          GroupDimension.byCurrency(),
        ],
      );
      await ledger.save(expense(id: 'tx-1', amount: '50'));
      await ledger.save(expense(id: 'tx-2', amount: '30', currency: 'EUR'));
      await ledger.save(expense(id: 'tx-3', amount: '10'));

      final fromView = ledger.viewResult('by-account-currency')!.result;
      final fromQuery = await ledger.query(
        const LedgerFilter(),
        groupBy: const [
          GroupDimension.byAccount(),
          GroupDimension.byCurrency(),
        ],
      );

      // Stats must match exactly, and the set of leaf (account, currency)
      // pairs with their per-currency sums must agree.
      expect(fromView.stats, fromQuery.stats);
      expect(_leafSumsByPath(fromView), _leafSumsByPath(fromQuery));
    });
  });
}

/// Flatten a [QueryResult] into `path -> sumByCurrency` for parity
/// comparison. Path is a `|`-joined string of group-key descriptors.
Map<String, Map<CurrencyCode, Decimal>> _leafSumsByPath(QueryResult result) {
  final out = <String, Map<CurrencyCode, Decimal>>{};
  void walk(QueryResult node, List<String> path) {
    final children = node.children.toList();
    if (children.isEmpty) {
      out[path.join('|')] = node.stats.sumByCurrency;
      return;
    }
    for (final child in children) {
      walk(child, [...path, child.key.toString()]);
    }
  }

  walk(result, const []);
  return out;
}
