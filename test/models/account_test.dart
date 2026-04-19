import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/account.dart';

void main() {
  group('Account', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates with required fields', () {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Checking',
        type: AccountType.asset,
        createdAt: now,
      );

      expect(account.path, 'Chase::Checking');
      expect(account.type, AccountType.asset);
      expect(account.isVirtual, false);
      expect(account.deleted, false);
    });

    test('parses hierarchical path segments', () {
      final account = Account(
        id: 'acc-1',
        path: 'Fidelity::401k',
        type: AccountType.asset,
        createdAt: now,
      );

      expect(account.pathSegments, ['Fidelity', '401k']);
      expect(account.group, 'Fidelity');
      expect(account.displayName, '401k');
    });

    test('handles flat path (no hierarchy)', () {
      final account = Account(
        id: 'acc-2',
        path: 'Tax Account',
        type: AccountType.expense,
        isVirtual: true,
        createdAt: now,
      );

      expect(account.pathSegments, ['Tax Account']);
      expect(account.group, 'Tax Account');
      expect(account.displayName, 'Tax Account');
      expect(account.isVirtual, true);
    });

    test('serializes to and from JSON', () {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Checking',
        type: AccountType.asset,
        notes: 'Primary checking',
        createdAt: now,
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored, account);
    });

    test('round-trips through JSON string', () {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Savings',
        type: AccountType.asset,
        createdAt: now,
      );

      final jsonString = jsonEncode(account.toJson());
      final restored = Account.fromJson(jsonDecode(jsonString));

      expect(restored, account);
    });
  });
}
