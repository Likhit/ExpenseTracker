import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';

void main() {
  group('Transaction', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates a simple expense transaction', () {
      final tx = Transaction(
        id: const TransactionId('tx-1'),
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('acc-expense-food'),
            amount: Decimal.parse('50.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Food::Groceries'),
          ),
          Leg(
            accountId: const AccountId('acc-checking'),
            amount: Decimal.parse('-50.00'),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

      expect(tx.type, TransactionType.expense);
      expect(tx.legs, hasLength(2));
      expect(tx.deleted, false);
    });

    test('creates a cross-currency transfer with metadata', () {
      final tx = Transaction(
        id: const TransactionId('tx-2'),
        date: now,
        description: 'Buy AAPL',
        type: TransactionType.transfer,
        legs: [
          Leg(
            accountId: const AccountId('acc-checking'),
            amount: Decimal.parse('-2000.00'),
            currencyCode: const CurrencyCode('USD'),
          ),
          Leg(
            accountId: const AccountId('acc-fidelity'),
            amount: Decimal.parse('10.00'),
            currencyCode: const CurrencyCode('AAPL'),
          ),
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

      expect(tx.metadata, isNotNull);
      expect(tx.metadata!['exchangeRate']['inverse'], 200.0);
    });

    test('serializes to and from JSON', () {
      final tx = Transaction(
        id: const TransactionId('tx-1'),
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('acc-food'),
            amount: Decimal.parse('50.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Food::Groceries'),
          ),
          Leg(
            accountId: const AccountId('acc-checking'),
            amount: Decimal.parse('-50.00'),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

      final json = tx.toJson();
      final restored = Transaction.fromJson(json);

      expect(restored, tx);
    });

    test('round-trips through JSON string', () {
      final tx = Transaction(
        id: const TransactionId('tx-1'),
        date: now,
        description: 'Salary',
        type: TransactionType.income,
        legs: [
          Leg(
            accountId: const AccountId('acc-income-salary'),
            amount: Decimal.parse('-5000.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Salary'),
          ),
          Leg(
            accountId: const AccountId('acc-checking'),
            amount: Decimal.parse('5000.00'),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

      final jsonString = jsonEncode(tx.toJson());
      final restored = Transaction.fromJson(jsonDecode(jsonString));

      expect(restored, tx);
    });
  });

  group('Leg', () {
    test('serializes to and from JSON', () {
      final leg = Leg(
        accountId: const AccountId('acc-1'),
        amount: Decimal.parse('100.50'),
        currencyCode: const CurrencyCode('USD'),
        categoryPath: const CategoryPath('Food::Snacks'),
      );

      final json = leg.toJson();
      final restored = Leg.fromJson(json);

      expect(restored, leg);
    });
  });

  group('Transaction.validate', () {
    final now = DateTime.utc(2026, 4, 19);

    Transaction txWithLegs(List<Leg> legs, {Map<String, dynamic>? metadata}) =>
        Transaction(
          id: const TransactionId('tx-1'),
          date: now,
          description: 'test',
          type: TransactionType.expense,
          legs: legs,
          metadata: metadata,
          createdAt: now,
        );

    test('rejects transaction with fewer than 2 legs', () {
      final tx = txWithLegs([
        Leg(
          accountId: const AccountId('checking'),
          amount: Decimal.parse('-50.00'),
          currencyCode: const CurrencyCode('USD'),
        ),
      ]);

      final result = tx.validate();
      expect(result.isValid, false);
      expect(result.errorMessage, contains('at least 2 legs'));
    });

    test('accepts balanced same-currency transaction', () {
      final tx = txWithLegs([
        Leg(
            accountId: const AccountId('checking'),
            amount: Decimal.parse('-50.00'),
            currencyCode: const CurrencyCode('USD')),
        Leg(
            accountId: const AccountId('food'),
            amount: Decimal.parse('50.00'),
            currencyCode: const CurrencyCode('USD')),
      ]);

      expect(tx.validate().isValid, true);
    });

    test('rejects unbalanced same-currency transaction', () {
      final tx = txWithLegs([
        Leg(
            accountId: const AccountId('checking'),
            amount: Decimal.parse('-50.00'),
            currencyCode: const CurrencyCode('USD')),
        Leg(
            accountId: const AccountId('food'),
            amount: Decimal.parse('49.00'),
            currencyCode: const CurrencyCode('USD')),
      ]);

      final result = tx.validate();
      expect(result.isValid, false);
      expect(result.errorMessage, contains('do not balance'));
    });

    test('accepts cross-currency transfer with metadata', () {
      final tx = txWithLegs(
        [
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
      );

      expect(tx.validate().isValid, true);
    });

    test('rejects cross-currency transfer without metadata', () {
      final tx = txWithLegs([
        Leg(
            accountId: const AccountId('checking'),
            amount: Decimal.parse('-2000.00'),
            currencyCode: const CurrencyCode('USD')),
        Leg(
            accountId: const AccountId('fidelity'),
            amount: Decimal.parse('10'),
            currencyCode: const CurrencyCode('AAPL')),
      ]);

      final result = tx.validate();
      expect(result.isValid, false);
      expect(result.errorMessage, contains('exchangeRate'));
    });

    test('rejects transaction with 3+ currencies', () {
      final tx = txWithLegs(
        [
          Leg(
              accountId: const AccountId('a'),
              amount: Decimal.parse('-100'),
              currencyCode: const CurrencyCode('USD')),
          Leg(
              accountId: const AccountId('b'),
              amount: Decimal.parse('80'),
              currencyCode: const CurrencyCode('EUR')),
          Leg(
              accountId: const AccountId('c'),
              amount: Decimal.parse('10'),
              currencyCode: const CurrencyCode('GBP')),
        ],
        metadata: {
          'exchangeRate': {'from': 'USD', 'to': 'EUR'},
        },
      );

      final result = tx.validate();
      expect(result.isValid, false);
      expect(result.errorMessage, contains('exactly 2 currencies'));
    });

    test('accepts multi-leg same-currency paycheck', () {
      final tx = txWithLegs([
        Leg(
            accountId: const AccountId('income-salary'),
            amount: Decimal.parse('-5000.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Salary')),
        Leg(
            accountId: const AccountId('expense-tax'),
            amount: Decimal.parse('1500.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Tax')),
        Leg(
            accountId: const AccountId('401k'),
            amount: Decimal.parse('500.00'),
            currencyCode: const CurrencyCode('USD')),
        Leg(
            accountId: const AccountId('checking'),
            amount: Decimal.parse('3000.00'),
            currencyCode: const CurrencyCode('USD')),
      ]);

      expect(tx.validate().isValid, true);
    });

    test('rejects a category on the built-in Expense account leg', () {
      final tx = Transaction(
        id: const TransactionId('tx-bad-expense-cat'),
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('chase'),
            amount: Decimal.parse('-50.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Food'),
          ),
          Leg(
            accountId: Account.expenseId,
            amount: Decimal.parse('50.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Food'),
          ),
        ],
        createdAt: now,
      );
      expect(tx.validate().isValid, false);
    });

    test('rejects a category on the built-in Income account leg', () {
      final tx = Transaction(
        id: const TransactionId('tx-bad-income-cat'),
        date: now,
        description: 'Salary',
        type: TransactionType.income,
        legs: [
          Leg(
            accountId: Account.incomeId,
            amount: Decimal.parse('-1000.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Salary'),
          ),
          Leg(
            accountId: const AccountId('chase'),
            amount: Decimal.parse('1000.00'),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: const CategoryPath('Salary'),
          ),
        ],
        createdAt: now,
      );
      expect(tx.validate().isValid, false);
    });
  });
}
