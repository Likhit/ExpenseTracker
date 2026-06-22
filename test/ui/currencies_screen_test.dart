import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/ui/screens/currencies_screen.dart';
import 'package:expense_tracker/ui/widgets/currency_edit_dialog.dart';

import 'test_harness.dart';

void main() {
  Currency currency(String id, String code, String name, CurrencyType type,
          {String? symbol, int decimalPlaces = 2}) =>
      Currency(
        id: CurrencyId(id),
        code: CurrencyCode(code),
        name: name,
        type: type,
        symbol: symbol,
        decimalPlaces: decimalPlaces,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  group('CurrenciesScreen', () {
    testWidgets('groups currencies by type', (tester) async {
      await pumpWithLedger(
        tester,
        const CurrenciesScreen(),
        seed: (ledger) async {
          await ledger.save(
              currency('usd', 'USD', 'US Dollar', CurrencyType.fiat, symbol: r'$'));
          await ledger.save(
              currency('eur', 'EUR', 'Euro', CurrencyType.fiat, symbol: '€'));
          await ledger.save(currency('aapl', 'AAPL', 'Apple Inc.',
              CurrencyType.stock,
              decimalPlaces: 4));
          await ledger.save(currency('btc', 'BTC', 'Bitcoin', CurrencyType.crypto,
              symbol: '₿', decimalPlaces: 8));
        },
      );

      expect(find.text('Fiat'), findsOneWidget);
      expect(find.text('Stock'), findsOneWidget);
      expect(find.text('Crypto'), findsOneWidget);
      expect(find.text(r'USD · US Dollar'), findsOneWidget);
      expect(find.text(r'AAPL · Apple Inc.'), findsOneWidget);
      expect(find.text(r'BTC · Bitcoin'), findsOneWidget);
    });

    testWidgets('add flow creates a new currency', (tester) async {
      await pumpWithLedger(tester, const CurrenciesScreen());

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New currency'));
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyEditDialog), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Code'), 'cad');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'Canadian Dollar');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await drain(tester);

      expect(find.byType(CurrencyEditDialog), findsNothing);
      // Code was uppercased on save.
      expect(find.text('CAD · Canadian Dollar'), findsOneWidget);
    });

    testWidgets('duplicate code is rejected with an inline error',
        (tester) async {
      await pumpWithLedger(
        tester,
        const CurrenciesScreen(),
        seed: (ledger) async {
          await ledger.save(currency('usd', 'USD', 'US Dollar',
              CurrencyType.fiat));
        },
      );

      await tester.tap(find.widgetWithText(FloatingActionButton, 'New currency'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Code'), 'USD');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'Different');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      // Dialog still open, validator surfaces the clash.
      expect(find.byType(CurrencyEditDialog), findsOneWidget);
      expect(find.text('A currency with this code already exists'),
          findsOneWidget);
    });
  });
}
