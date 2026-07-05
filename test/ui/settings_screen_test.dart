import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/services/app_settings.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/settings_store.dart';
import 'package:expense_tracker/ui/screens/settings_screen.dart';

import 'test_harness.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);

  Currency currency(String code, String name) => Currency(
        id: CurrencyId(code.toLowerCase()),
        code: CurrencyCode(code),
        name: name,
        type: CurrencyType.fiat,
        createdAt: now,
      );

  Future<AppSettings> readSettings(WidgetTester tester, SettingsStore s) async =>
      (await tester.runAsync(() => s.load()))!;

  Future<SettingsStore> seededStore(WidgetTester tester,
      [AppSettings? seed]) async {
    late final SettingsStore store;
    await tester.runAsync(() async => store = await memorySettingsStore(seed));
    return store;
  }

  Future<void> seedCurrencies(LedgerService l) async {
    await l.save(currency('USD', 'US Dollar'));
    await l.save(currency('EUR', 'Euro'));
  }

  group('SettingsScreen', () {
    testWidgets('theme selection persists and updates the subtitle',
        (tester) async {
      final store = await seededStore(tester);
      await pumpWithLedger(tester, const SettingsScreen(),
          settingsStore: store);

      // Default is System.
      expect(find.text('System'), findsOneWidget);

      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await drain(tester);

      expect((await readSettings(tester, store)).themeMode, AppThemeMode.dark);
      // Subtitle now reflects the choice.
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('default currency selection persists', (tester) async {
      final store = await seededStore(tester);
      await pumpWithLedger(tester, const SettingsScreen(),
          seed: seedCurrencies, settingsStore: store);

      expect(find.text('Not set'), findsOneWidget);

      await tester.tap(find.text('Default currency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR · Euro'));
      await drain(tester);

      expect((await readSettings(tester, store)).defaultCurrencyCode, 'EUR');
      // Subtitle updates to the picked code.
      expect(find.text('EUR'), findsOneWidget);
    });

    testWidgets('sync folder shows local-only by default', (tester) async {
      final store = await seededStore(tester);
      await pumpWithLedger(tester, const SettingsScreen(),
          settingsStore: store);
      expect(find.text('Local only (this device)'), findsOneWidget);
    });
  });
}
