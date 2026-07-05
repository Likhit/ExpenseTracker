import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/category.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/ui/screens/expense_income_entry_screen.dart';
import 'package:expense_tracker/ui/screens/transactions_screen.dart';
import 'package:expense_tracker/ui/screens/transfer_entry_screen.dart';

import 'test_harness.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);

  Account asset(String id, String path) => Account(
        id: AccountId(id),
        path: path,
        type: AccountType.asset,
        createdAt: now,
      );

  Currency usd() => Currency(
        id: const CurrencyId('usd'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        symbol: r'$',
        createdAt: now,
      );

  Currency eur() => Currency(
        id: const CurrencyId('eur'),
        code: const CurrencyCode('EUR'),
        name: 'Euro',
        type: CurrencyType.fiat,
        symbol: '€',
        createdAt: now,
      );

  Category foodCat() => Category(
        id: const CategoryId('food'),
        path: const CategoryPath('Food'),
        parentType: TransactionType.expense,
        createdAt: now,
      );

  Category salaryCat() => Category(
        id: const CategoryId('salary'),
        path: const CategoryPath('Salary'),
        parentType: TransactionType.income,
        createdAt: now,
      );

  /// Real I/O is only safe inside `runAsync`; widget-test fake-async would
  /// deadlock on the file read otherwise.
  Future<List<Transaction>> readTxs(WidgetTester tester, LedgerService l) async {
    final result = await tester.runAsync(() => l.transactions.getAll());
    return result ?? const [];
  }

  group('TransactionsScreen FAB', () {
    testWidgets('FAB opens the type chooser with three tiles', (tester) async {
      await pumpWithLedger(tester, const TransactionsScreen());

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });
  });

  group('Expense entry', () {
    testWidgets('happy path saves a 2-leg expense', (tester) async {
      final ledger = await pumpWithLedger(
        tester,
        const ExpenseIncomeEntryScreen(type: TransactionType.expense),
        seed: (l) async {
          await l.save(usd());
          await l.save(foodCat());
          await l.save(asset('chase', 'Chase::Checking'));
        },
      );

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '50.25');

      // Pick the category — drain lets the picker's categoriesProvider yield.
      await tester.tap(find.text('Tap to pick').first);
      await drain(tester);
      await tester.tap(find.text('Food'));
      await drain(tester);

      // Pick the source account.
      await tester.tap(find.text('Tap to pick'));
      await drain(tester);
      await tester.tap(find.text('Checking'));
      await drain(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await drain(tester);

      final saved = await readTxs(tester, ledger);
      expect(saved, hasLength(1));
      final tx = saved.single;
      expect(tx.type, TransactionType.expense);
      expect(tx.legs, hasLength(2));
      final assetLeg = tx.legs.firstWhere((l) => l.accountId.value == 'chase');
      expect(assetLeg.amount.toString(), '-50.25');
      expect(assetLeg.categoryPath?.value, 'Food');
      final sink =
          tx.legs.firstWhere((l) => l.accountId == Account.expenseId);
      expect(sink.amount.toString(), '50.25');
      expect(sink.categoryPath, isNull);
    });

    testWidgets('missing amount surfaces inline error and does not save',
        (tester) async {
      final ledger = await pumpWithLedger(
        tester,
        const ExpenseIncomeEntryScreen(type: TransactionType.expense),
        seed: (l) async {
          await l.save(usd());
        },
      );

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await drain(tester);

      expect(find.text('Enter an amount'), findsOneWidget);
      final saved = await readTxs(tester, ledger);
      expect(saved, isEmpty);
    });
  });

  group('Expense edit', () {
    Transaction existingExpense() => Transaction(
          id: const TransactionId('tx-edit'),
          date: now,
          description: 'Lunch',
          type: TransactionType.expense,
          legs: [
            Leg(
              accountId: const AccountId('chase'),
              amount: Decimal.parse('-12.50'),
              currencyCode: const CurrencyCode('USD'),
              categoryPath: const CategoryPath('Food'),
            ),
            Leg(
              accountId: Account.expenseId,
              amount: Decimal.parse('12.50'),
              currencyCode: const CurrencyCode('USD'),
            ),
          ],
          createdAt: now,
        );

    testWidgets('titles the screen "Edit expense" and prefills category/account',
        (tester) async {
      await pumpWithLedger(
        tester,
        ExpenseIncomeEntryScreen(
            type: TransactionType.expense, existing: existingExpense()),
        seed: (l) async {
          await l.save(usd());
          await l.save(foodCat());
          await l.save(asset('chase', 'Chase::Checking'));
        },
      );

      // Edit-mode title, not "New expense".
      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.text('New expense'), findsNothing);
      // Category and account tiles are prefilled from the existing legs.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Chase::Checking'), findsOneWidget);
      // No "Tap to pick" placeholders remain for those tiles.
      expect(find.text('Tap to pick'), findsNothing);
    });
  });

  group('Category picker hierarchy', () {
    testWidgets('drills from a root into its descendants, then picks a leaf',
        (tester) async {
      final ledger = await pumpWithLedger(
        tester,
        const ExpenseIncomeEntryScreen(type: TransactionType.expense),
        seed: (l) async {
          await l.save(usd());
          await l.save(asset('chase', 'Chase::Checking'));
          await l.save(Category(
            id: const CategoryId('food'),
            path: const CategoryPath('Food'),
            parentType: TransactionType.expense,
            createdAt: now,
          ));
          await l.save(Category(
            id: const CategoryId('groceries'),
            path: const CategoryPath('Food::Groceries'),
            parentType: TransactionType.expense,
            createdAt: now,
          ));
          await l.save(Category(
            id: const CategoryId('snacks'),
            path: const CategoryPath('Food::Snacks'),
            parentType: TransactionType.expense,
            createdAt: now,
          ));
        },
      );

      await tester.tap(find.text('Tap to pick').first);
      await drain(tester);

      // Root grid/list shows Food but not its children yet.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);

      // Tapping the root (which has descendants) drills in.
      await tester.tap(find.text('Food'));
      await drain(tester);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Snacks'), findsOneWidget);

      // Tapping a leaf selects it and closes the picker.
      await tester.tap(find.text('Groceries'));
      await drain(tester);
      expect(find.text('Food::Groceries'), findsOneWidget);

      // Sanity: no transaction saved yet (we only picked a category).
      final saved = await readTxs(tester, ledger);
      expect(saved, isEmpty);
    });
  });

  group('Income entry', () {
    testWidgets('happy path saves a 2-leg income', (tester) async {
      final ledger = await pumpWithLedger(
        tester,
        const ExpenseIncomeEntryScreen(type: TransactionType.income),
        seed: (l) async {
          await l.save(usd());
          await l.save(salaryCat());
          await l.save(asset('chase', 'Chase::Checking'));
        },
      );

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '1000');
      await tester.tap(find.text('Tap to pick').first);
      await drain(tester);
      await tester.tap(find.text('Salary'));
      await drain(tester);
      await tester.tap(find.text('Tap to pick'));
      await drain(tester);
      await tester.tap(find.text('Checking'));
      await drain(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await drain(tester);

      final saved = await readTxs(tester, ledger);
      expect(saved, hasLength(1));
      final tx = saved.single;
      expect(tx.type, TransactionType.income);
      final assetLeg = tx.legs.firstWhere((l) => l.accountId.value == 'chase');
      expect(assetLeg.amount.toString(), '1000');
      expect(assetLeg.categoryPath?.value, 'Salary');
      final source =
          tx.legs.firstWhere((l) => l.accountId == Account.incomeId);
      expect(source.amount.toString(), '-1000');
    });
  });

  group('Transfer entry', () {
    testWidgets('same-currency transfer balances both legs to one amount',
        (tester) async {
      final ledger = await pumpWithLedger(
        tester,
        const TransferEntryScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(asset('a', 'Chase::Checking'));
          await l.save(asset('b', 'Cash'));
        },
      );

      // From.
      await tester.tap(find.text('Tap to pick').first);
      await drain(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Checking'));
      await drain(tester);
      // To.
      await tester.tap(find.text('Tap to pick'));
      await drain(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Cash'));
      await drain(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '75');

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await drain(tester);

      final saved = await readTxs(tester, ledger);
      expect(saved, hasLength(1));
      final tx = saved.single;
      expect(tx.type, TransactionType.transfer);
      expect(tx.metadata, isNull); // No exchangeRate for same-currency.
      final outflow = tx.legs.firstWhere((l) => l.accountId.value == 'a');
      final inflow = tx.legs.firstWhere((l) => l.accountId.value == 'b');
      expect(outflow.amount.toString(), '-75');
      expect(inflow.amount.toString(), '75');
      expect(outflow.categoryPath, isNull);
      expect(inflow.categoryPath, isNull);
    });

    testWidgets('hides cross-currency form when both legs share the currency',
        (tester) async {
      await pumpWithLedger(
        tester,
        const TransferEntryScreen(),
        seed: (l) async {
          await l.save(usd());
          await l.save(eur());
          await l.save(asset('a', 'Chase::Checking'));
          await l.save(asset('b', 'Cash'));
        },
      );

      // Default currency is the same on both sides, so the single-amount form
      // is shown. The cross-currency dual-amount fields are absent until the
      // user picks a different To-currency.
      expect(find.widgetWithText(TextFormField, 'Amount'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'From amount'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'To amount'), findsNothing);
      // The "To currency" picker is exposed so users can switch to cross-
      // currency mode.
      expect(find.text('To currency'), findsOneWidget);
    });
  });
}
