import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/category.dart';

void main() {
  group('Category', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates with required fields', () {
      final category = Category(
        id: 'cat-1',
        path: 'Food',
        parentType: CategoryParentType.expense,
        createdAt: now,
      );

      expect(category.path, 'Food');
      expect(category.parentType, CategoryParentType.expense);
      expect(category.deleted, false);
    });

    test('parses deep hierarchical path', () {
      final category = Category(
        id: 'cat-2',
        path: 'Food::Snacks::Cake',
        parentType: CategoryParentType.expense,
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
        path: 'Salary',
        parentType: CategoryParentType.income,
        createdAt: now,
      );

      expect(category.depth, 1);
      expect(category.root, 'Salary');
      expect(category.displayName, 'Salary');
    });

    test('serializes to and from JSON', () {
      final category = Category(
        id: 'cat-1',
        path: 'Food::Groceries',
        parentType: CategoryParentType.expense,
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
        path: 'Health Care::Dental',
        parentType: CategoryParentType.expense,
        createdAt: now,
      );

      final jsonString = jsonEncode(category.toJson());
      final restored = Category.fromJson(jsonDecode(jsonString));

      expect(restored, category);
    });
  });
}
