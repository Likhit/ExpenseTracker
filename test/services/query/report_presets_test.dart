import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/report_presets.dart';

void main() {
  final now = DateTime.utc(2026, 6, 15, 9, 30);

  Account acct(String id, AccountType type, {bool deleted = false}) => Account(
        id: AccountId(id),
        path: id,
        type: type,
        createdAt: DateTime.utc(2026, 1, 1),
        deleted: deleted,
      );

  group('monthRange', () {
    test('spans the whole calendar month, inclusive of the last instant', () {
      final range = monthRange(now);
      expect(range.from, DateTime.utc(2026, 6, 1));
      // Just before July 1 — the last microsecond of June.
      expect(range.to, DateTime.utc(2026, 7, 1).subtract(
          const Duration(microseconds: 1)));
      expect(range.to.isBefore(DateTime.utc(2026, 7, 1)), isTrue);
      expect(range.to.isAfter(DateTime.utc(2026, 6, 30, 23, 59, 59)), isTrue);
    });

    test('rolls over the year in December', () {
      final range = monthRange(DateTime.utc(2026, 12, 9));
      expect(range.from, DateTime.utc(2026, 12, 1));
      expect(range.to, DateTime.utc(2027, 1, 1).subtract(
          const Duration(microseconds: 1)));
    });

    test('preserves UTC-ness of the input', () {
      expect(monthRange(now).from.isUtc, isTrue);
      expect(monthRange(DateTime(2026, 6, 15)).from.isUtc, isFalse);
    });
  });

  group('month filters', () {
    test('expensesInMonth constrains type, range, and drops the Expense sink',
        () {
      final filter = expensesInMonth(now);
      expect(filter.types, {TransactionType.expense});
      expect(filter.excludeAccounts, {Account.expenseId});
      expect(filter.from, DateTime.utc(2026, 6, 1));
    });

    test('incomeInMonth constrains type and drops the Income source', () {
      final filter = incomeInMonth(now);
      expect(filter.types, {TransactionType.income});
      expect(filter.excludeAccounts, {Account.incomeId});
    });
  });

  group('netWorthAccounts', () {
    test('keeps active asset and liability accounts, drops the rest', () {
      final accounts = [
        acct('chase', AccountType.asset),
        acct('card', AccountType.liability),
        acct('old', AccountType.asset, deleted: true),
        acct('equity', AccountType.equity),
        Account(
          id: Account.expenseId,
          path: 'Expense',
          type: AccountType.expense,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      expect(netWorthAccounts(accounts),
          {const AccountId('chase'), const AccountId('card')});
    });
  });

  group('groupBy presets', () {
    test('spendingByCategory uses the requested depth', () {
      expect(spendingByCategory(), [const GroupDimension.byCategory()]);
      expect(spendingByCategory(depth: 2),
          [const GroupDimension.byCategory(depth: 2)]);
    });

    test('incomeVsExpenseOverTime groups by time then transaction type', () {
      expect(incomeVsExpenseOverTime(TimeBucket.month), [
        const GroupDimension.byTime(TimeBucket.month),
        const GroupDimension.byTransactionType(),
      ]);
    });

    test('netWorthOverTime groups by time only', () {
      expect(netWorthOverTime(TimeBucket.month),
          [const GroupDimension.byTime(TimeBucket.month)]);
    });
  });
}
