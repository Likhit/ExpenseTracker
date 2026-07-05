import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/models/leg.dart';
import 'package:expense_tracker/models/transaction.dart';
import 'package:expense_tracker/providers/ledger_provider.dart';
import 'package:expense_tracker/providers/reports_provider.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/query/ledger_group.dart';
import 'package:expense_tracker/services/query/ledger_stats.dart';

void main() {
  late Directory dir;
  late LedgerService ledger;
  final now = DateTime.utc(2026, 6, 1);

  Transaction expense(String id, String amount, String category) => Transaction(
        id: TransactionId(id),
        date: now,
        description: '',
        type: TransactionType.expense,
        legs: [
          Leg(
            accountId: const AccountId('chase'),
            amount: -Decimal.parse(amount),
            currencyCode: const CurrencyCode('USD'),
            categoryPath: CategoryPath(category),
          ),
          Leg(
            accountId: Account.expenseId,
            amount: Decimal.parse(amount),
            currencyCode: const CurrencyCode('USD'),
          ),
        ],
        createdAt: now,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reports_provider_test_');
    ledger = await LedgerService.create(
      accountsPath: '${dir.path}/accounts.jsonl',
      categoriesPath: '${dir.path}/categories.jsonl',
      currenciesPath: '${dir.path}/currencies.jsonl',
      transactionsPath: '${dir.path}/transactions.jsonl',
    );
  });

  tearDown(() async {
    await ledger.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer containerWith(LedgerService l) {
    final container = ProviderContainer(
      overrides: [ledgerProvider.overrideWith((ref) async => l)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Decimal? foodSum(QueryResult? result) {
    if (result == null) return null;
    final food = result.children.where(
        (c) => c.key == const GroupKey.category(CategoryPath('Food')));
    if (food.isEmpty) return null;
    return food.first.stats.sumByCurrency[const CurrencyCode('USD')];
  }

  test('report provider groups by category and stays live on save', () async {
    await ledger.save(expense('e1', '40', 'Food'));
    final container = containerWith(ledger);
    const spec = ReportSpec(groupBy: [GroupDimension.byCategory()]);

    // Keep the stream subscribed so it re-yields on subsequent changes.
    container.listen(reportProvider(spec), (_, _) {}, fireImmediately: true);
    final first = await container.read(reportProvider(spec).future);
    expect(foodSum(first), Decimal.parse('-40'));

    // A later save flows through ledger.changes into the same spec's stream.
    await ledger.save(expense('e2', '10', 'Food'));
    Decimal? live;
    for (var i = 0; i < 50 && live != Decimal.parse('-50'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      live = foodSum(container.read(reportProvider(spec)).value);
    }
    expect(live, Decimal.parse('-50'));
  });

  test('same ReportSpec value resolves to the same family provider', () {
    const a = ReportSpec(groupBy: [GroupDimension.byCategory()]);
    const b = ReportSpec(groupBy: [GroupDimension.byCategory()]);
    const c = ReportSpec(groupBy: [GroupDimension.byCurrency()]);
    // Value equality on the family key → equal provider objects (shared
    // element); a different spec is a different provider.
    expect(reportProvider(a), reportProvider(b));
    expect(reportProvider(a), isNot(reportProvider(c)));
  });
}
