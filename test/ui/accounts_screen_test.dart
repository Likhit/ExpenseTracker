import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/ui/screens/accounts_screen.dart';
import 'package:expense_tracker/ui/widgets/account_edit_dialog.dart';

import 'test_harness.dart';

void main() {
  Account asset(String id, String path) => Account(
        id: AccountId(id),
        path: path,
        type: AccountType.asset,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('AccountsScreen', () {
    testWidgets('renders the system-accounts section with both built-ins',
        (tester) async {
      await pumpWithLedger(tester, const AccountsScreen());

      expect(find.text('System accounts'), findsOneWidget);
      // Both built-ins render — their leaf name and their type label both
      // contain the same word, so we expect at least one match per name.
      expect(find.text('Expense'), findsAtLeastNWidgets(1));
      expect(find.text('Income'), findsAtLeastNWidgets(1));
      // The built-in tiles are read-only — no trailing popup menu on them.
      expect(find.byWidgetPredicate((w) => w is PopupMenuButton),
          findsNothing);
    });

    testWidgets('groups user accounts by their root `::` segment',
        (tester) async {
      await pumpWithLedger(
        tester,
        const AccountsScreen(),
        seed: (ledger) async {
          await ledger.save(asset('chase-c', 'Chase::Checking'));
          await ledger.save(asset('chase-s', 'Chase::Savings'));
          await ledger.save(asset('cash', 'Cash'));
        },
      );

      // Group headers for the two roots, plus the leaf names.
      expect(find.text('Cash'), findsAtLeastNWidgets(1));
      expect(find.text('Chase'), findsOneWidget);
      expect(find.text('Checking'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
    });

    testWidgets('add flow creates an account that shows up in the list',
        (tester) async {
      await pumpWithLedger(tester, const AccountsScreen());

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New account'));
      await drain(tester);
      expect(find.byType(AccountEditDialog), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Path'), 'Chase::Checking');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await drain(tester);

      expect(find.byType(AccountEditDialog), findsNothing);
      expect(find.text('Checking'), findsOneWidget);
      expect(find.text('Chase'), findsOneWidget);
    });

    testWidgets('soft-deleting hides the account by default, shown by toggle',
        (tester) async {
      await pumpWithLedger(
        tester,
        const AccountsScreen(),
        seed: (ledger) async {
          await ledger.save(asset('cash', 'Cash'));
        },
      );

      expect(find.text('Cash'), findsAtLeastNWidgets(1));

      // Open the row's popup menu (animated overlay) and pick Delete. The
      // popup is typed `PopupMenuButton<_AccountAction>` (private generic), so
      // we match by predicate rather than `byType`.
      await tester.tap(
          find.byWidgetPredicate((w) => w is PopupMenuButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // Confirm dialog should now be present — tap its Delete button.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete')));
      await drain(tester);

      expect(find.text('Cash'), findsNothing);

      await tester.tap(find.byTooltip('Show deleted'));
      await drain(tester);
      expect(find.text('Cash'), findsAtLeastNWidgets(1));
    });
  });
}
