import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/providers/storage_providers.dart';
import 'package:expense_tracker/ui/screens/transactions/transaction_list_screen.dart';

void main() {
  group('TransactionListScreen', () {
    final now = DateTime.utc(2026, 4, 19);

    Widget buildApp({
      List<Transaction> transactions = const [],
      List<Account> accounts = const [],
    }) {
      return ProviderScope(
        overrides: [
          transactionsProvider.overrideWith(() {
            return _FakeTransactionsNotifier(transactions);
          }),
          accountsProvider.overrideWith(() {
            return _FakeAccountsNotifier(accounts);
          }),
        ],
        child: const MaterialApp(home: TransactionListScreen()),
      );
    }

    testWidgets('shows empty state when no transactions', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(
          find.text('No transactions yet. Tap + to add one.'), findsOneWidget);
    });

    testWidgets('shows transactions with type icons', (tester) async {
      await tester.pumpWidget(buildApp(
        transactions: [
          Transaction(
            id: 'tx-1',
            date: now,
            description: 'Groceries',
            type: TransactionType.expense,
            legs: [
              const Leg(
                accountId: 'acc-1',
                amount: '-50.00',
                currencyCode: 'USD',
              ),
              const Leg(
                accountId: 'acc-1',
                amount: '50.00',
                currencyCode: 'USD',
                categoryPath: 'Food::Groceries',
              ),
            ],
            createdAt: now,
          ),
        ],
        accounts: [
          Account(
            id: 'acc-1',
            path: 'Chase::Checking',
            type: AccountType.asset,
            createdAt: now,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      // Expense icon
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('shows add menu on FAB tap', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
    });
  });
}

class _FakeTransactionsNotifier extends TransactionsNotifier {
  final List<Transaction> _transactions;
  _FakeTransactionsNotifier(this._transactions);

  @override
  Future<List<Transaction>> build() async => _transactions;
}

class _FakeAccountsNotifier extends AccountsNotifier {
  final List<Account> _accounts;
  _FakeAccountsNotifier(this._accounts);

  @override
  Future<List<Account>> build() async => _accounts;
}
