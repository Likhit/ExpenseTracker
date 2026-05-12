import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/category.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/transaction.dart';

void main() {
  group('Category', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates with required fields', () {
      final category = Category(
        id: 'cat-1',
        path: const CategoryPath('Food'),
        parentType: TransactionType.expense,
        createdAt: now,
      );

      expect(category.path, const CategoryPath('Food'));
      expect(category.parentType, TransactionType.expense);
      expect(category.deleted, false);
    });

    test('parses deep hierarchical path', () {
      final category = Category(
        id: 'cat-2',
        path: const CategoryPath('Food::Snacks::Cake'),
        parentType: TransactionType.expense,
        createdAt: now,
      );

      expect(category.pathSegments, ['Food', 'Snacks', 'Cake']);
      expect(category.root, 'Food');
      expect(category.displayName, 'Cake');
      expect(category.depth, 3);
    });

    test('root category has depth 1', () {
      final category = Category(
        id: 'cat-1',
        path: const CategoryPath('Salary'),
        parentType: TransactionType.income,
        createdAt: now,
      );

      expect(category.depth, 1);
      expect(category.root, 'Salary');
      expect(category.displayName, 'Salary');
    });

    test('serializes to and from JSON', () {
      final category = Category(
        id: 'cat-1',
        path: const CategoryPath('Food::Groceries'),
        parentType: TransactionType.expense,
        icon: 'restaurant',
        color: '#FF5722',
        createdAt: now,
      );

      final json = category.toJson();
      final restored = Category.fromJson(json);

      expect(restored, category);
    });

    test('round-trips through JSON string', () {
      final category = Category(
        id: 'cat-1',
        path: const CategoryPath('Health Care::Dental'),
        parentType: TransactionType.expense,
        createdAt: now,
      );

      final jsonString = jsonEncode(category.toJson());
      final restored = Category.fromJson(jsonDecode(jsonString));

      expect(restored, category);
    });
  });
}
