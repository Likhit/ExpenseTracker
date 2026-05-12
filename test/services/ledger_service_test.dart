import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';

void main() {
  late LedgerService ledger;
  final now = DateTime.utc(2026, 4, 19);

  setUp(() {
    ledger = LedgerService();
  });

  group('computeBalances', () {
    test('returns empty map for no transactions', () {
      final balances = ledger.computeBalances([]);
      expect(balances, isEmpty);
    });

    test('computes single-currency expense correctly', () {
      final tx = Transaction(
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
      );

      final balances = ledger.computeBalances([tx]);

      expect(balances[const AccountId('checking')]![const CurrencyCode('USD')],
          Decimal.parse('-50.00'));
      expect(
          balances[const AccountId('expense-food')]![
              const CurrencyCode('USD')],
          Decimal.parse('50.00'));
    });

    test('accumulates multiple transactions for same account', () {
      final transactions = [
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
      ];

      final balances = ledger.computeBalances(transactions);

      expect(balances[const AccountId('checking')]![const CurrencyCode('USD')],
          Decimal.parse('4950.00'));
    });

    test('handles multi-currency accounts', () {
      final tx = Transaction(
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
      );

      final balances = ledger.computeBalances([tx]);

      expect(balances[const AccountId('checking')]![const CurrencyCode('USD')],
          Decimal.parse('-2000.00'));
      expect(balances[const AccountId('fidelity')]![const CurrencyCode('AAPL')],
          Decimal.parse('10'));
      expect(
          balances[const AccountId('fidelity')]!
              .containsKey(const CurrencyCode('USD')),
          false);
    });
  });
}
