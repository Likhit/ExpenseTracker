import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/ledger_state.dart';

void main() {
  late Directory dirA;
  late Directory dirB;
  final now = DateTime.utc(2026, 6, 1);

  Decimal d(String s) => Decimal.parse(s);

  Transaction expense({
    required String id,
    required String amount,
    String description = 'x',
  }) =>
      Transaction(
        id: TransactionId(id),
        date: now,
        description: description,
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('chase'),
            amount: d('-$amount'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Food'),
          ),
          Leg(
            accountId: Account.expenseId,
            amount: d(amount),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

  Future<LedgerService> open(Directory dir) => LedgerService.create(
        accountsPath: '${dir.path}/accounts.jsonl',
        categoriesPath: '${dir.path}/categories.jsonl',
        currenciesPath: '${dir.path}/currencies.jsonl',
        transactionsPath: '${dir.path}/transactions.jsonl',
      );

  Future<void> copyTransactions(Directory from, Directory to, String asName) =>
      File('${from.path}/transactions.jsonl').copy('${to.path}/$asName');

  // Sets up dirA as "ours" with a `transactions (1).jsonl` conflict copy:
  // both chains share [shared] (identical lineIds, via a file copy) then
  // diverge — ours with [ours], the copy with [theirs].
  Future<void> fork({
    required List<Transaction> shared,
    required List<Transaction> ours,
    required List<Transaction> theirs,
  }) async {
    final a = await open(dirA);
    for (final tx in shared) {
      await a.save(tx);
    }
    // B starts from exactly our shared prefix.
    await copyTransactions(dirA, dirB, 'transactions.jsonl');

    for (final tx in ours) {
      await a.save(tx);
    }
    final b = await open(dirB);
    for (final tx in theirs) {
      await b.save(tx);
    }
    // B's divergent file lands next to ours as the sync conflict copy.
    await copyTransactions(dirB, dirA, 'transactions (1).jsonl');
  }

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('syncA_');
    dirB = await Directory.systemTemp.createTemp('syncB_');
  });

  tearDown(() async {
    for (final dir in [dirA, dirB]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  group('clean divergence', () {
    test('merges both sides into one chain, deletes the copy, stays Ready',
        () async {
      await fork(
        shared: [expense(id: 't1', amount: '10')],
        ours: [expense(id: 't2', amount: '20')],
        theirs: [expense(id: 't3', amount: '30')],
      );

      final ledger = await open(dirA);
      expect(ledger.state, isA<LedgerReady>());
      final ids = (await ledger.transactions.getAll()).map((t) => t.id.value);
      expect(ids, containsAll(['t1', 't2', 't3']));
      expect(
          await File('${dirA.path}/transactions (1).jsonl').exists(), isFalse);
    });
  });

  group('conflicting edits', () {
    test('surfaces a conflict and rejects writes until resolved', () async {
      await fork(
        shared: [expense(id: 't1', amount: '10')],
        ours: [expense(id: 't1', amount: '15', description: 'ours')],
        theirs: [expense(id: 't1', amount: '99', description: 'theirs')],
      );

      final ledger = await open(dirA);
      expect(ledger.state, isA<LedgerConflicted>());
      final conflicts = (ledger.state as LedgerConflicted).conflicts;
      expect(conflicts, hasLength(1));

      // Writes are rejected while conflicted.
      await expectLater(
        ledger.save(expense(id: 't9', amount: '1')),
        throwsStateError,
      );

      // Keep our version.
      await ledger.resolveConflicts({conflicts.single: ConflictChoice.ours});
      expect(ledger.state, isA<LedgerReady>());
      final t1 = await ledger.transactions.get(const TransactionId('t1'));
      expect(t1!.description, 'ours');

      // Writes work again.
      final result = await ledger.save(expense(id: 't9', amount: '1'));
      expect(result.isValid, isTrue);
    });

    test('choosing theirs keeps the other side', () async {
      await fork(
        shared: [expense(id: 't1', amount: '10')],
        ours: [expense(id: 't1', amount: '15', description: 'ours')],
        theirs: [expense(id: 't1', amount: '99', description: 'theirs')],
      );

      final ledger = await open(dirA);
      final conflicts = (ledger.state as LedgerConflicted).conflicts;
      await ledger.resolveConflicts({conflicts.single: ConflictChoice.theirs});

      final t1 = await ledger.transactions.get(const TransactionId('t1'));
      expect(t1!.description, 'theirs');
    });
  });

  group('view catch-up', () {
    test('runtime sync brings a registered view current over merged txs',
        () async {
      final a = await open(dirA);
      await a.save(expense(id: 't1', amount: '10'));
      await copyTransactions(dirA, dirB, 'transactions.jsonl'); // shared prefix
      await a.save(expense(id: 't2', amount: '20'));

      final view = await a.register(name: 'totals');
      expect(view.result.stats.count, 4); // t1, t2 × 2 legs

      // B diverges with t3; drop it in as a conflict copy, then sync at runtime.
      final b = await open(dirB);
      await b.save(expense(id: 't3', amount: '30'));
      await copyTransactions(dirB, dirA, 'transactions (1).jsonl');

      await a.sync();
      expect(a.state, isA<LedgerReady>());
      // t3 replayed onto the live view — not a full rebuild.
      expect(a.viewResult('totals').result.stats.count, 6);
    });
  });
}
