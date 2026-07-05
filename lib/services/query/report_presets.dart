import '../../models/account.dart';
import '../../models/ids.dart';
import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';

/// Reusable `(LedgerFilter, groupBy)` building blocks for the report screens,
/// so the dashboard, spending, and trend views share one definition of "this
/// month", "spending by category", etc. rather than re-deriving them.
///
/// Pure and side-effect-free: the account-dependent presets take the account
/// set as a parameter (the provider layer resolves it from `ledger.accounts`).

/// Inclusive [from]/[to] instants spanning the calendar month containing [now].
/// [to] is the last microsecond of the month so a `LedgerFilter` with these
/// bounds includes every transaction dated within it. Preserves [now]'s
/// UTC-ness so it compares cleanly against however transaction dates were made.
({DateTime from, DateTime to}) monthRange(DateTime now) {
  final from = _startOfMonth(now.year, now.month, utc: now.isUtc);
  final nextMonth = now.month == 12
      ? _startOfMonth(now.year + 1, 1, utc: now.isUtc)
      : _startOfMonth(now.year, now.month + 1, utc: now.isUtc);
  return (from: from, to: nextMonth.subtract(const Duration(microseconds: 1)));
}

DateTime _startOfMonth(int year, int month, {required bool utc}) =>
    utc ? DateTime.utc(year, month, 1) : DateTime(year, month, 1);

/// Expenses within the month containing [now] — for the dashboard "Expenses"
/// card and spending breakdown. Excludes the built-in Expense-account legs so
/// stats read as the asset-side outflow, not the doubled balancing pair.
LedgerFilter expensesInMonth(DateTime now) {
  final range = monthRange(now);
  return LedgerFilter(
    types: const {TransactionType.expense},
    excludeAccounts: {Account.expenseId},
    from: range.from,
    to: range.to,
  );
}

/// Income within the month containing [now] — the dashboard "Income" card.
/// Excludes the built-in Income-account legs (see [expensesInMonth]).
LedgerFilter incomeInMonth(DateTime now) {
  final range = monthRange(now);
  return LedgerFilter(
    types: const {TransactionType.income},
    excludeAccounts: {Account.incomeId},
    from: range.from,
    to: range.to,
  );
}

/// Balance-bearing legs of the accounts whose running total is "net worth":
/// user asset and liability accounts (never the built-in Income/Expense sinks).
/// [asOf] optionally caps the range for a point-in-time balance.
LedgerFilter netWorthFilter(Set<AccountId> accounts, {DateTime? asOf}) =>
    LedgerFilter(accounts: accounts, to: asOf);

/// The account ids that make up net worth: active asset and liability accounts.
/// Excludes soft-deleted accounts and the built-in Income/Expense buckets
/// (which are `income`/`expense` type, not asset/liability).
Set<AccountId> netWorthAccounts(Iterable<Account> accounts) => {
      for (final a in accounts)
        if (!a.deleted &&
            (a.type == AccountType.asset || a.type == AccountType.liability))
          a.id,
    };

/// Group expenses by category truncated to [depth] — the spending breakdown.
List<GroupDimension> spendingByCategory({int depth = 1}) =>
    [GroupDimension.byCategory(depth: depth)];

/// Group by time bucket then transaction type — the income-vs-expense trend.
List<GroupDimension> incomeVsExpenseOverTime(TimeBucket bucket) =>
    [GroupDimension.byTime(bucket), const GroupDimension.byTransactionType()];

/// Group by time bucket — feed to `cumulativeSeries` for the net-worth trend.
List<GroupDimension> netWorthOverTime(TimeBucket bucket) =>
    [GroupDimension.byTime(bucket)];
