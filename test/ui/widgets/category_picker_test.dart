import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/models/category.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/providers/storage_providers.dart';
import 'package:expense_tracker/ui/widgets/category_picker.dart';

void main() {
  group('CategoryPicker', () {
    final now = DateTime.utc(2026, 4, 19);

    final testCategories = [
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
        path: 'Transport',
        parentType: TransactionType.expense,
        icon: 'directions_car',
        createdAt: now,
      ),
    ];

    Widget buildApp({
      required ValueChanged<String> onSelected,
      String? initialPath,
    }) {
      return ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(() {
            return _FakeCategoriesNotifier(testCategories);
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CategoryPicker(
                parentType: TransactionType.expense,
                initialPath: initialPath,
                onSelected: onSelected,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows root categories as chips', (tester) async {
      await tester.pumpWidget(buildApp(onSelected: (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
    });

    testWidgets('tapping a chip selects it', (tester) async {
      String? selected;
      await tester.pumpWidget(
          buildApp(onSelected: (v) => selected = v));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(selected, 'Food');
    });

    testWidgets('typing shows search results', (tester) async {
      await tester.pumpWidget(buildApp(onSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Sna');
      await tester.pumpAndSettle();

      expect(find.text('Food::Snacks'), findsOneWidget);
    });

    testWidgets('typing new path shows create option', (tester) async {
      await tester.pumpWidget(buildApp(onSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Food::Takeout');
      await tester.pumpAndSettle();

      expect(find.textContaining('Create "Food::Takeout"'), findsOneWidget);
    });
  });
}

class _FakeCategoriesNotifier extends CategoriesNotifier {
  final List<Category> _categories;
  _FakeCategoriesNotifier(this._categories);

  @override
  Future<List<Category>> build() async => _categories;
}
