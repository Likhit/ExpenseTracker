import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/models/leg.dart';
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
        id: 'tx-1',
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          const Leg(
            accountId: 'checking',
            amount: '-50.00',
            currencyCode: 'USD',
          ),
          const Leg(
            accountId: 'expense-food',
            amount: '50.00',
            currencyCode: 'USD',
            categoryPath: 'Food',
          ),
        ],
        createdAt: now,
      );

      final balances = ledger.computeBalances([tx]);

      expect(balances['checking']!['USD'], Decimal.parse('-50.00'));
      expect(balances['expense-food']!['USD'], Decimal.parse('50.00'));
    });

    test('accumulates multiple transactions for same account', () {
      final transactions = [
        Transaction(
          id: 'tx-1',
          date: now,
          description: 'Groceries',
          type: TransactionType.expense,
          legs: [
            const Leg(
                accountId: 'checking',
                amount: '-50.00',
                currencyCode: 'USD'),
            const Leg(
                accountId: 'food',
                amount: '50.00',
                currencyCode: 'USD',
                categoryPath: 'Food'),
          ],
          createdAt: now,
        ),
        Transaction(
          id: 'tx-2',
          date: now,
          description: 'Salary',
          type: TransactionType.income,
          legs: [
            const Leg(
                accountId: 'checking',
                amount: '5000.00',
                currencyCode: 'USD'),
            const Leg(
                accountId: 'salary',
                amount: '-5000.00',
                currencyCode: 'USD',
                categoryPath: 'Salary'),
          ],
          createdAt: now,
        ),
      ];

      final balances = ledger.computeBalances(transactions);

      // checking: -50 + 5000 = 4950
      expect(balances['checking']!['USD'], Decimal.parse('4950.00'));
    });

    test('handles multi-currency accounts', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Buy AAPL',
        type: TransactionType.transfer,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-2000.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'fidelity',
              amount: '10',
              currencyCode: 'AAPL'),
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

      expect(balances['checking']!['USD'], Decimal.parse('-2000.00'));
      expect(balances['fidelity']!['AAPL'], Decimal.parse('10'));
      expect(balances['fidelity']!.containsKey('USD'), false);
    });
  });

  group('accountBalance', () {
    test('returns empty map for unknown account', () {
      final result = ledger.accountBalance('unknown', []);
      expect(result, isEmpty);
    });

    test('returns balances for specific account', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Deposit',
        type: TransactionType.income,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '1000.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'income',
              amount: '-1000.00',
              currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.accountBalance('checking', [tx]);
      expect(result['USD'], Decimal.parse('1000.00'));
    });
  });

  group('validate', () {
    test('rejects transaction with fewer than 2 legs', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Bad',
        type: TransactionType.expense,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-50.00',
              currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, false);
      expect(result.errorMessage, contains('at least 2 legs'));
    });

    test('accepts balanced same-currency transaction', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-50.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'food',
              amount: '50.00',
              currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, true);
    });

    test('rejects unbalanced same-currency transaction', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Bad',
        type: TransactionType.expense,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-50.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'food',
              amount: '49.00',
              currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, false);
      expect(result.errorMessage, contains('do not balance'));
    });

    test('accepts cross-currency transfer with metadata', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Buy AAPL',
        type: TransactionType.transfer,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-2000.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'fidelity',
              amount: '10',
              currencyCode: 'AAPL'),
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

      final result = ledger.validate(tx);
      expect(result.isValid, true);
    });

    test('rejects cross-currency transfer without metadata', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Bad transfer',
        type: TransactionType.transfer,
        legs: [
          const Leg(
              accountId: 'checking',
              amount: '-2000.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'fidelity',
              amount: '10',
              currencyCode: 'AAPL'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, false);
      expect(result.errorMessage, contains('exchangeRate'));
    });

    test('rejects transaction with 3+ currencies', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Bad',
        type: TransactionType.transfer,
        legs: [
          const Leg(
              accountId: 'a', amount: '-100', currencyCode: 'USD'),
          const Leg(
              accountId: 'b', amount: '80', currencyCode: 'EUR'),
          const Leg(
              accountId: 'c', amount: '10', currencyCode: 'GBP'),
        ],
        metadata: {
          'exchangeRate': {'from': 'USD', 'to': 'EUR'},
        },
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, false);
      expect(result.errorMessage, contains('exactly 2 currencies'));
    });

    test('rejects transaction with invalid amount', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Bad',
        type: TransactionType.expense,
        legs: [
          const Leg(
              accountId: 'a', amount: 'not-a-number', currencyCode: 'USD'),
          const Leg(
              accountId: 'b', amount: '50', currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, false);
      expect(result.errorMessage, contains('Invalid amount'));
    });

    test('accepts multi-leg same-currency paycheck', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Paycheck',
        type: TransactionType.income,
        legs: [
          const Leg(
              accountId: 'income-salary',
              amount: '-5000.00',
              currencyCode: 'USD',
              categoryPath: 'Salary'),
          const Leg(
              accountId: 'expense-tax',
              amount: '1500.00',
              currencyCode: 'USD',
              categoryPath: 'Tax'),
          const Leg(
              accountId: '401k',
              amount: '500.00',
              currencyCode: 'USD'),
          const Leg(
              accountId: 'checking',
              amount: '3000.00',
              currencyCode: 'USD'),
        ],
        createdAt: now,
      );

      final result = ledger.validate(tx);
      expect(result.isValid, true);
    });
  });

  group('validateLegs', () {
    test('validates pre-save legs', () {
      final legs = [
        const Leg(
            accountId: 'a', amount: '-100.00', currencyCode: 'USD'),
        const Leg(
            accountId: 'b', amount: '100.00', currencyCode: 'USD'),
      ];

      final result = ledger.validateLegs(legs, null);
      expect(result.isValid, true);
    });

    test('rejects unbalanced pre-save legs', () {
      final legs = [
        const Leg(
            accountId: 'a', amount: '-100.00', currencyCode: 'USD'),
        const Leg(
            accountId: 'b', amount: '99.00', currencyCode: 'USD'),
      ];

      final result = ledger.validateLegs(legs, null);
      expect(result.isValid, false);
    });
  });
}
