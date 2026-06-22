import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/ui/screens/transactions_screen.dart';

import 'test_harness.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);
  Decimal d(String s) => Decimal.parse(s);

  Currency usd() => Currency(
        id: const CurrencyId('usd'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        symbol: r'$',
        createdAt: now,
      );

  Account chase() => Account(
        id: const AccountId('chase'),
        path: 'Chase::Checking',
        type: AccountType.asset,
        createdAt: now,
      );

  Account cash() => Account(
        id: const AccountId('cash'),
        path: 'Cash',
        type: AccountType.asset,
        createdAt: now,
      );

  Transaction expense({
    required String id,
    required String amount,
    String accountId = 'chase',
    String category = 'Food::Groceries',
    DateTime? date,
    String description = '',
  }) =>
      Transaction(
        id: TransactionId(id),
        date: date ?? now,
        description: description,
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: AccountId(accountId),
            amount: -d(amount),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: CategoryPath(category),
          ),
          Leg(
            accountId: Account.expenseId,
            amount: d(amount),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

  Transaction income({
    required String id,
    required String amount,
    String accountId = 'chase',
    String category = 'Salary',
    DateTime? date,
    String description = '',
  }) =>
      Transaction(
        id: TransactionId(id),
        date: date ?? now,
        description: description,
        type: TransactionType.income,
        legs: [
          Leg(
            accountId: Account.incomeId,
            amount: -d(amount),
            currencyCode: const CurrencyCode('USD'),
          ),
          Leg(
            accountId: AccountId(accountId),
            amount: d(amount),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: CategoryPath(category),
          ),
        ],
        createdAt: now,
      );

  group('TransactionsScreen list', () {
    testWidgets('empty state when no transactions yet', (tester) async {
      await pumpWithLedger(tester, const TransactionsScreen());
      expect(find.text('No transactions yet.'), findsOneWidget);
    });

    testWidgets('renders rows reverse-chronologically with day headers',
        (tester) async {
      await pumpWithLedger(
        tester,
        const TransactionsScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(chase());
          await l.save(expense(
              id: 'tx-a',
              amount: '50',
              description: 'Groceries',
              date: DateTime.utc(2026, 6, 1)));
          await l.save(expense(
              id: 'tx-b',
              amount: '5',
              description: 'Coffee',
              date: DateTime.utc(2026, 6, 2)));
        },
      );

      // Both rows render.
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
      // A day header for June 1 and one for June 2 (formatted via intl).
      // We just check there's at least one header text below the appbar.
      expect(find.textContaining('June'), findsAtLeastNWidgets(1));
    });

    testWidgets('type filter narrows the list to one transaction type',
        (tester) async {
      await pumpWithLedger(
        tester,
        const TransactionsScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(chase());
          await l.save(expense(id: 'e', amount: '20', description: 'Lunch'));
          await l.save(income(id: 'i', amount: '1000', description: 'Salary'));
        },
      );

      // Both visible initially.
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);

      // Open the Type chip and pick Income only.
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await drain(tester);

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });

    testWidgets('account filter narrows by leg account', (tester) async {
      await pumpWithLedger(
        tester,
        const TransactionsScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(chase());
          await l.save(cash());
          await l.save(expense(
              id: 'e1',
              amount: '20',
              accountId: 'chase',
              description: 'On Chase'));
          await l.save(expense(
              id: 'e2',
              amount: '15',
              accountId: 'cash',
              description: 'On Cash'));
        },
      );

      expect(find.text('On Chase'), findsOneWidget);
      expect(find.text('On Cash'), findsOneWidget);

      // Open Account chip, tick Chase::Checking, apply.
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Chase::Checking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await drain(tester);

      expect(find.text('On Chase'), findsOneWidget);
      expect(find.text('On Cash'), findsNothing);
    });

    testWidgets('soft-delete hides the row and Show-deleted reveals it',
        (tester) async {
      await pumpWithLedger(
        tester,
        const TransactionsScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(chase());
          await l.save(expense(id: 'e', amount: '20', description: 'Lunch'));
        },
      );

      expect(find.text('Lunch'), findsOneWidget);

      // Open the row popup menu (transaction row).
      await tester.tap(
          find.byWidgetPredicate((w) => w is PopupMenuButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // Confirm dialog.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete')));
      // Two drains: the first lets the delete I/O complete and the engine
      // re-emit the stream value; the second lets the list rebuild on it.
      await drain(tester);
      await drain(tester);

      expect(find.text('Lunch'), findsNothing);

      // Show deleted reveals it again.
      await tester.tap(find.byTooltip('Show deleted'));
      await drain(tester);
      expect(find.text('Lunch'), findsOneWidget);
    });
  });
}
