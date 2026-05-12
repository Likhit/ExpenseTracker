import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';

void main() {
  late Directory tempDir;
  late LedgerService ledger;
  final now = DateTime.utc(2026, 4, 19);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ledger_test_');
    ledger = LedgerService(
      accountsPath: '${tempDir.path}/accounts.jsonl',
      categoriesPath: '${tempDir.path}/categories.jsonl',
      currenciesPath: '${tempDir.path}/currencies.jsonl',
      transactionsPath: '${tempDir.path}/transactions.jsonl',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LedgerService construction', () {
    test('exposes the four repositories', () {
      expect(ledger.accounts, isNotNull);
      expect(ledger.categories, isNotNull);
      expect(ledger.currencies, isNotNull);
      expect(ledger.transactions, isNotNull);
    });

    test('repositories are empty on a fresh ledger', () async {
      expect(await ledger.accounts.getAll(), isEmpty);
      expect(await ledger.categories.getAll(), isEmpty);
      expect(await ledger.currencies.getAll(), isEmpty);
      expect(await ledger.transactions.getAll(), isEmpty);
    });

    test('writes through the facade persist to disk', () async {
      await ledger.transactions.save(
        Transaction(
          id: const TransactionId('tx-1'),
          date: now,
          description: 'Test',
          type: TransactionType.expense,
          legs: [
            Leg(
              accountId: const AccountId('checking'),
              amount: Decimal.parse('-10.00'),
              currencyCode: const CurrencyCode('USD'),
            ),
            Leg(
              accountId: const AccountId('food'),
              amount: Decimal.parse('10.00'),
              currencyCode: const CurrencyCode('USD'),
            ),
          ],
          createdAt: now,
        ),
      );

      final reread = LedgerService(
        accountsPath: '${tempDir.path}/accounts.jsonl',
        categoriesPath: '${tempDir.path}/categories.jsonl',
        currenciesPath: '${tempDir.path}/currencies.jsonl',
        transactionsPath: '${tempDir.path}/transactions.jsonl',
      );
      final txs = await reread.transactions.getAll();
      expect(txs, hasLength(1));
      expect(txs.first.description, 'Test');
    });
  });

  group('computeBalances', () {
    test('returns empty map when no transactions', () async {
      expect(await ledger.computeBalances(), isEmpty);
    });

    test('computes single-currency expense correctly', () async {
      await ledger.transactions.save(
        Transaction(
          id: const TransactionId('tx-1'),
          date: now,
          description: 'Groceries',
          type: TransactionType.expense,
          legs: [
            Leg(
              accountId: const AccountId('checking'),
              amount: Decimal.parse('-50.00'),
              currencyCode: const CurrencyCode('USD'),
            ),
            Leg(
              accountId: const AccountId('expense-food'),
              amount: Decimal.parse('50.00'),
              currencyCode: const CurrencyCode('USD'),
              categoryPath: const CategoryPath('Food'),
            ),
          ],
          createdAt: now,
        ),
      );

      final balances = await ledger.computeBalances();

      expect(
        balances[const AccountId('checking')]![const CurrencyCode('USD')],
        Decimal.parse('-50.00'),
      );
      expect(
        balances[const AccountId('expense-food')]![const CurrencyCode('USD')],
        Decimal.parse('50.00'),
      );
    });

    test('accumulates multiple transactions for same account', () async {
      await ledger.transactions.saveAll([
        Transaction(
          id: const TransactionId('tx-1'),
          date: now,
          description: 'Groceries',
          type: TransactionType.expense,
          legs: [
            Leg(
                accountId: const AccountId('checking'),
                amount: Decimal.parse('-50.00'),
                currencyCode: const CurrencyCode('USD')),
            Leg(
                accountId: const AccountId('food'),
                amount: Decimal.parse('50.00'),
                currencyCode: const CurrencyCode('USD'),
                categoryPath: const CategoryPath('Food')),
          ],
          createdAt: now,
        ),
        Transaction(
          id: const TransactionId('tx-2'),
          date: now,
          description: 'Salary',
          type: TransactionType.income,
          legs: [
            Leg(
                accountId: const AccountId('checking'),
                amount: Decimal.parse('5000.00'),
                currencyCode: const CurrencyCode('USD')),
            Leg(
                accountId: const AccountId('salary'),
                amount: Decimal.parse('-5000.00'),
                currencyCode: const CurrencyCode('USD'),
                categoryPath: const CategoryPath('Salary')),
          ],
          createdAt: now,
        ),
      ]);

      final balances = await ledger.computeBalances();

      expect(
        balances[const AccountId('checking')]![const CurrencyCode('USD')],
        Decimal.parse('4950.00'),
      );
    });

    test('handles multi-currency accounts', () async {
      await ledger.transactions.save(
        Transaction(
          id: const TransactionId('tx-1'),
          date: now,
          description: 'Buy AAPL',
          type: TransactionType.transfer,
          legs: [
            Leg(
                accountId: const AccountId('checking'),
                amount: Decimal.parse('-2000.00'),
                currencyCode: const CurrencyCode('USD')),
            Leg(
                accountId: const AccountId('fidelity'),
                amount: Decimal.parse('10'),
                currencyCode: const CurrencyCode('AAPL')),
          ],
          metadata: {
            'exchangeRate': {
              'from': 'USD',
              'to': 'AAPL',
              'rate': 0.005,
              'inverse': 200.0,
            },
          },
          createdAt: now,
        ),
      );

      final balances = await ledger.computeBalances();

      expect(
        balances[const AccountId('checking')]![const CurrencyCode('USD')],
        Decimal.parse('-2000.00'),
      );
      expect(
        balances[const AccountId('fidelity')]![const CurrencyCode('AAPL')],
        Decimal.parse('10'),
      );
      expect(
        balances[const AccountId('fidelity')]!
            .containsKey(const CurrencyCode('USD')),
        false,
      );
    });
  });
}
