import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/providers/storage_providers.dart';
import 'package:expense_tracker/ui/screens/settings/currency_list_screen.dart';

void main() {
  group('CurrencyListScreen', () {
    final now = DateTime.utc(2026, 4, 19);

    Widget buildApp({List<Currency> currencies = const []}) {
      return ProviderScope(
        overrides: [
          currenciesProvider.overrideWith(() {
            return _FakeCurrenciesNotifier(currencies);
          }),
        ],
        child: const MaterialApp(home: CurrencyListScreen()),
      );
    }

    testWidgets('shows currencies grouped by type', (tester) async {
      await tester.pumpWidget(buildApp(currencies: [
        Currency(
          id: 'cur-1',
          code: 'USD',
          name: 'US Dollar',
          type: CurrencyType.fiat,
          symbol: r'$',
          createdAt: now,
        ),
        Currency(
          id: 'cur-2',
          code: 'AAPL',
          name: 'Apple Inc.',
          type: CurrencyType.stock,
          decimalPlaces: 0,
          createdAt: now,
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Fiat Currencies'), findsOneWidget);
      expect(find.text('Stocks'), findsOneWidget);
      expect(find.text('USD — US Dollar'), findsOneWidget);
      expect(find.text('AAPL — Apple Inc.'), findsOneWidget);
    });

    testWidgets('opens add dialog on FAB tap', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('New Currency'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('shows empty state with no currencies', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No currencies.'), findsOneWidget);
    });
  });
}

class _FakeCurrenciesNotifier extends CurrenciesNotifier {
  final List<Currency> _currencies;
  _FakeCurrenciesNotifier(this._currencies);

  @override
  Future<List<Currency>> build() async => _currencies;
}
