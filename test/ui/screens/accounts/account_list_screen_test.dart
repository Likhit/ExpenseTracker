import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/providers/storage_providers.dart';
import 'package:expense_tracker/ui/screens/accounts/account_list_screen.dart';

void main() {
  group('AccountListScreen', () {
    Widget buildApp({List<Account> accounts = const []}) {
      return ProviderScope(
        overrides: [
          accountsProvider.overrideWith(() {
            return _FakeAccountsNotifier(accounts);
          }),
        ],
        child: const MaterialApp(home: AccountListScreen()),
      );
    }

    testWidgets('shows empty state when no accounts', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No accounts yet. Tap + to add one.'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows accounts grouped by hierarchy', (tester) async {
      final now = DateTime.utc(2026, 4, 19);
      await tester.pumpWidget(buildApp(accounts: [
        Account(
          id: 'acc-1',
          path: 'Chase::Checking',
          type: AccountType.asset,
          createdAt: now,
        ),
        Account(
          id: 'acc-2',
          path: 'Chase::Savings',
          type: AccountType.asset,
          createdAt: now,
        ),
        Account(
          id: 'acc-3',
          path: 'Tax Account',
          type: AccountType.expense,
          isVirtual: true,
          createdAt: now,
        ),
      ]));
      await tester.pumpAndSettle();

      // Group header
      expect(find.text('Chase'), findsOneWidget);
      // Leaf names
      expect(find.text('Checking'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
      // Flat account
      expect(find.text('Tax Account'), findsOneWidget);
    });

    testWidgets('opens add dialog on FAB tap', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('New Account'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
    });
  });
}

class _FakeAccountsNotifier extends AccountsNotifier {
  final List<Account> _accounts;
  _FakeAccountsNotifier(this._accounts);

  @override
  Future<List<Account>> build() async => _accounts;
}
