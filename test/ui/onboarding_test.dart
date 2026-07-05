import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/services/app_settings.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/settings_store.dart';
import 'package:expense_tracker/ui/screens/onboarding/onboarding_screen.dart';

import 'test_harness.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);

  Currency usd() => Currency(
        id: const CurrencyId('usd'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

  Future<SettingsStore> seededStore(WidgetTester tester) async {
    late final SettingsStore store;
    await tester.runAsync(() async => store = await memorySettingsStore());
    return store;
  }

  Future<AppSettings> readSettings(WidgetTester tester, SettingsStore s) async =>
      (await tester.runAsync(() => s.load()))!;

  Future<List<Account>> userAccounts(
      WidgetTester tester, LedgerService l) async {
    final all = await tester.runAsync(() => l.accounts.getAll()) ?? const [];
    return [
      for (final a in all)
        if (a.id != Account.expenseId && a.id != Account.incomeId) a,
    ];
  }

  group('OnboardingScreen', () {
    testWidgets('walks all steps, creates the first account, and completes',
        (tester) async {
      final store = await seededStore(tester);
      final ledger = await pumpWithLedger(
        tester,
        const OnboardingScreen(),
        seed: (l) async => l.save(usd()),
        settingsStore: store,
      );

      // Step 1: Welcome.
      expect(find.textContaining('Track every'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await drain(tester);

      // Step 2: Sync folder — default local only.
      expect(find.text('Local only (this device)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await drain(tester);

      // Step 3: Default currency — pick USD.
      await tester.tap(find.text('USD · US Dollar'));
      await drain(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await drain(tester);

      // Step 4: First account — default name "Checking", Finish.
      expect(find.text('Your first account'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await drain(tester);

      final settings = await readSettings(tester, store);
      expect(settings.onboardingComplete, isTrue);
      expect(settings.defaultCurrencyCode, 'USD');

      final accounts = await userAccounts(tester, ledger);
      expect(accounts, hasLength(1));
      expect(accounts.single.path, 'Checking');
      expect(accounts.single.type, AccountType.asset);
    });

    testWidgets('Skip setup completes without creating an account',
        (tester) async {
      final store = await seededStore(tester);
      final ledger = await pumpWithLedger(
        tester,
        const OnboardingScreen(),
        seed: (l) async => l.save(usd()),
        settingsStore: store,
      );

      await tester.tap(find.text('Skip setup'));
      await drain(tester);

      expect((await readSettings(tester, store)).onboardingComplete, isTrue);
      expect(await userAccounts(tester, ledger), isEmpty);
    });
  });
}
