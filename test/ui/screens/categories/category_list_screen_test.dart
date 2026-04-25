import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/models/category.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/providers/storage_providers.dart';
import 'package:expense_tracker/ui/screens/categories/category_list_screen.dart';

void main() {
  group('CategoryListScreen', () {
    Widget buildApp({List<Category> categories = const []}) {
      return ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(() {
            return _FakeCategoriesNotifier(categories);
          }),
        ],
        child: const MaterialApp(home: CategoryListScreen()),
      );
    }

    testWidgets('shows expense and income tabs', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
    });

    testWidgets('shows empty state with no categories', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No categories yet.'), findsOneWidget);
    });

    testWidgets('shows expense categories grouped by root', (tester) async {
      final now = DateTime.utc(2026, 4, 19);
      await tester.pumpWidget(buildApp(categories: [
        Category(
          id: 'cat-1',
          path: 'Food',
          parentType: TransactionType.expense,
          icon: 'restaurant',
          createdAt: now,
        ),
        Category(
          id: 'cat-2',
          path: 'Food::Snacks',
          parentType: TransactionType.expense,
          createdAt: now,
        ),
        Category(
          id: 'cat-3',
          path: 'Salary',
          parentType: TransactionType.income,
          createdAt: now,
        ),
      ]));
      await tester.pumpAndSettle();

      // Expense tab should show Food group
      expect(find.text('Food'), findsWidgets);
      // Salary is on income tab, not visible initially
    });

    testWidgets('opens add dialog on FAB tap', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('New Category'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
    });
  });
}

class _FakeCategoriesNotifier extends CategoriesNotifier {
  final List<Category> _categories;
  _FakeCategoriesNotifier(this._categories);

  @override
  Future<List<Category>> build() async => _categories;
}
