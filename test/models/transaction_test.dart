import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/models/leg.dart';

void main() {
  group('Transaction', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates a simple expense transaction', () {
      final tx = Transaction(
        id: 'tx-1',
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          const Leg(
            accountId: 'acc-expense-food',
            amount: '50.00',
            currencyCode: 'USD',
            categoryPath: 'Food::Groceries',
          ),
          const Leg(
            accountId: 'acc-checking',
            amount: '-50.00',
            currencyCode: 'USD',
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
        id: 'tx-2',
        date: now,
        description: 'Buy AAPL',
        type: TransactionType.transfer,
        legs: [
          const Leg(
            accountId: 'acc-checking',
            amount: '-2000.00',
            currencyCode: 'USD',
          ),
          const Leg(
            accountId: 'acc-fidelity',
            amount: '10.00',
            currencyCode: 'AAPL',
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
        id: 'tx-1',
        date: now,
        description: 'Groceries',
        type: TransactionType.expense,
        legs: [
          const Leg(
            accountId: 'acc-food',
            amount: '50.00',
            currencyCode: 'USD',
            categoryPath: 'Food::Groceries',
          ),
          const Leg(
            accountId: 'acc-checking',
            amount: '-50.00',
            currencyCode: 'USD',
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
        id: 'tx-1',
        date: now,
        description: 'Salary',
        type: TransactionType.income,
        legs: [
          const Leg(
            accountId: 'acc-income-salary',
            amount: '-5000.00',
            currencyCode: 'USD',
            categoryPath: 'Salary',
          ),
          const Leg(
            accountId: 'acc-checking',
            amount: '5000.00',
            currencyCode: 'USD',
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
      const leg = Leg(
        accountId: 'acc-1',
        amount: '100.50',
        currencyCode: 'USD',
        categoryPath: 'Food::Snacks',
      );

      final json = leg.toJson();
      final restored = Leg.fromJson(json);

      expect(restored, leg);
    });
  });
}
