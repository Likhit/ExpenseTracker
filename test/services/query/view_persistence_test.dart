import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart' show Database;
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/query/ledger_filter.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';
import 'package:expense_tracker/services/query/view_store.dart';

void main() {
  late Directory tempDir;
  late Database db;
  final now = DateTime.utc(2026, 6, 1);

  Decimal d(String s) => Decimal.parse(s);

  Transaction expense({
    required String id,
    required String amount,
    String currency = 'USD',
    String category = 'Food::Groceries',
  }) =>
      Transaction(
        id: TransactionId(id),
        date: now,
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
      );

  // A new service over the same journal files. Pass [store] to persist views;
  // omit it to model a path that bypasses persistence.
  Future<LedgerService> ledger({ViewStore? store}) => LedgerService.create(
        accountsPath: '${tempDir.path}/accounts.jsonl',
        categoriesPath: '${tempDir.path}/categories.jsonl',
        currenciesPath: '${tempDir.path}/currencies.jsonl',
        transactionsPath: '${tempDir.path}/transactions.jsonl',
        viewStore: store,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('view_persist_');
    // A fresh, isolated in-memory database per test.
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('ViewStore round-trip', () {
    test('restores a grouped stats tree without replaying the journal',
        () async {
      const groupBy = [
        GroupDimension.byAccount(),
        GroupDimension.byCurrency(),
      ];
      final store = ViewStore(db);
      final a = await ledger(store: store);
      await a.register(name: 'by-account', groupBy: groupBy);
      await a.save(expense(id: 'tx-1', amount: '50'));
      await a.save(expense(id: 'tx-2', amount: '30', currency: 'EUR'));

      // "Restart": new service over the same files and the same store.
      final b = await ledger(store: store);
      final view = await b.register(name: 'by-account', groupBy: groupBy);

      final restored = view.result;
      expect(restored.stats.count, 4); // 2 legs × 2 txs
      final sums = {
        for (final account in restored.children)
          for (final currency in account.children)
            '${(account.key as AccountKey).id.value}/'
                '${(currency.key as CurrencyKey).code.value}':
                currency.stats.sumByCurrency,
      };
      expect(sums['chase/USD'], {const CurrencyCode('USD'): d('-50')});
      expect(sums['chase/EUR'], {const CurrencyCode('EUR'): d('-30')});
      expect(sums['${Account.expenseId.value}/USD'],
          {const CurrencyCode('USD'): d('50')});
    });

    test('restored leaves keep stats but mark rows as unhydrated', () async {
      final store = ViewStore(db);
      final a = await ledger(store: store);
      await a.register(name: 'totals');
      await a.save(expense(id: 'tx-1', amount: '50'));

      final b = await ledger(store: store);
      final view = await b.register(name: 'totals');

      final leaf = view.result as LeafResult;
      expect(leaf.stats.count, 2); // stats complete
      expect(leaf.source.materialized, isEmpty); // rows not loaded
      expect(leaf.source.checkpoint, isNotNull); // ...but flagged as on-disk
      expect(view.result.transactions, isEmpty);
    });
  });

  group('config drift', () {
    test('does not restore a snapshot built with a different filter',
        () async {
      final store = ViewStore(db);
      // Snapshot 'spending' as an unfiltered view over one expense.
      final a = await ledger(store: store);
      await a.register(name: 'spending');
      await a.save(expense(id: 'tx-1', amount: '50'));

      // "Restart" and register the SAME name with a filter that excludes the
      // expense leg's category. The journal hasn't changed (watermark would
      // match), so only the config check can prevent a stale restore.
      final b = await ledger(store: store);
      final view = await b.register(
        name: 'spending',
        filter: const LedgerFilter(categories: {CategoryPath('Travel')}),
      );

      // Recomputed under the new filter: nothing matches 'Travel'.
      expect(view.result.transactions, isEmpty);
      expect(view.result.stats.count, 0);
    });
  });

  group('staleness', () {
    test('recomputes when the journal moved past the watermark', () async {
      final store = ViewStore(db);
      final a = await ledger(store: store);
      await a.register(name: 'totals');
      await a.save(expense(id: 'tx-1', amount: '50')); // snapshot at this tip

      // A write through a store-less service advances the journal without
      // updating the snapshot.
      final bypass = await ledger();
      await bypass.save(expense(id: 'tx-2', amount: '20'));

      // Reopen with the now-stale store: watermark != tip → full recompute.
      final c = await ledger(store: store);
      final view = await c.register(name: 'totals');
      expect(view.result.stats.count, 4); // both txs folded in
      expect(view.result.transactions, hasLength(2)); // re-seeded, hydrated
      expect((view.result as LeafResult).source.checkpoint, isNull);
    });
  });

  group('mixed state', () {
    test('saves after a restore stack on top of the checkpoint', () async {
      final store = ViewStore(db);
      final a = await ledger(store: store);
      await a.register(name: 'totals');
      await a.save(expense(id: 'tx-1', amount: '50'));

      final b = await ledger(store: store);
      await b.register(name: 'totals');
      await b.save(expense(id: 'tx-2', amount: '20')); // new save after restore

      final result = b.viewResult('totals').result;
      expect(result.stats.count, 4); // tx-1 (checkpoint) + tx-2 (overlay)
      // Only the post-restore row is materialized; tx-1 stays behind the
      // checkpoint until lazy resolution (a later phase).
      expect(result.transactions.map((t) => t.id),
          {const TransactionId('tx-2')});
      expect((result as LeafResult).source.checkpoint, isNotNull);
    });
  });

  group('without a ViewStore', () {
    test('views still work; nothing is persisted', () async {
      final a = await ledger(); // no store
      await a.register(name: 'totals');
      await a.save(expense(id: 'tx-1', amount: '50'));
      expect(a.viewResult('totals').result.stats.count, 2);

      // A separate service with a store sees an empty database → seeds fresh.
      final store = ViewStore(db);
      final b = await ledger(store: store);
      final view = await b.register(name: 'totals');
      // Seeded by replay (the journal has tx-1), not restored from a snapshot.
      expect(view.result.stats.count, 2);
      expect((view.result as LeafResult).source.checkpoint, isNull);
    });
  });
}
