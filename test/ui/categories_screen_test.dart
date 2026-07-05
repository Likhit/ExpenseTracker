import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/category.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/ui/screens/categories_screen.dart';
import 'package:expense_tracker/ui/widgets/category_edit_dialog.dart';

import 'test_harness.dart';

void main() {
  Category cat(String id, String path,
          {TransactionType type = TransactionType.expense,
          String? icon,
          String? color}) =>
      Category(
        id: CategoryId(id),
        path: CategoryPath(path),
        parentType: type,
        icon: icon,
        color: color,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('CategoriesScreen', () {
    testWidgets('empty state appears when there are no categories yet',
        (tester) async {
      await pumpWithLedger(tester, const CategoriesScreen());

      expect(find.text('No categories yet'), findsOneWidget);
    });

    testWidgets('Expense tab shows roots and their descendants', (tester) async {
      await pumpWithLedger(
        tester,
        const CategoriesScreen(),
        seed: (ledger) async {
          await ledger.save(cat('food', 'Food', icon: 'food'));
          await ledger.save(cat('food-groc', 'Food::Groceries'));
          await ledger.save(cat('food-out', 'Food::Eating Out'));
          await ledger.save(cat('xpt', 'Transport', icon: 'transport'));
        },
      );

      // Both expense roots visible.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      // Subcounts.
      expect(find.text('2 subcategories'), findsOneWidget);

      // Expand the Food root to verify descendants render.
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Eating Out'), findsOneWidget);
    });

    testWidgets('tabs filter by parent type', (tester) async {
      await pumpWithLedger(
        tester,
        const CategoriesScreen(),
        seed: (ledger) async {
          await ledger.save(cat('xfood', 'Food'));
          await ledger.save(cat('isalary', 'Salary',
              type: TransactionType.income));
        },
      );

      // On the Expense tab Salary doesn't appear.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      // Switch to Income.
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Food'), findsNothing);
    });

    testWidgets('add flow creates a new root category', (tester) async {
      await pumpWithLedger(tester, const CategoriesScreen());

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New category'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryEditDialog), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'Food');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await drain(tester);

      expect(find.byType(CategoryEditDialog), findsNothing);
      expect(find.text('Food'), findsOneWidget);
    });
  });
}
