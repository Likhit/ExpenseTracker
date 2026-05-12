import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';

void main() {
  group('Currency', () {
    final now = DateTime.utc(2026, 4, 19);

    test('creates with required fields', () {
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      expect(currency.code, const CurrencyCode('USD'));
      expect(currency.type, CurrencyType.fiat);
      expect(currency.decimalPlaces, 2);
      expect(currency.deleted, false);
      expect(currency.symbol, isNull);
    });

    test('creates stock currency with custom decimal places', () {
      final currency = Currency(
        id: const CurrencyId('cur-2'),
        code: const CurrencyCode('AAPL'),
        name: 'Apple Inc.',
        type: CurrencyType.stock,
        decimalPlaces: 0,
        createdAt: now,
      );

      expect(currency.code, const CurrencyCode('AAPL'));
      expect(currency.type, CurrencyType.stock);
      expect(currency.decimalPlaces, 0);
    });

    test('serializes to and from JSON', () {
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        symbol: r'$',
        decimalPlaces: 2,
        createdAt: now,
      );

      final json = currency.toJson();
      final restored = Currency.fromJson(json);

      expect(restored, currency);
    });

    test('round-trips through JSON string', () {
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('BTC'),
        name: 'Bitcoin',
        type: CurrencyType.crypto,
        decimalPlaces: 8,
        createdAt: now,
      );

      final jsonString = jsonEncode(currency.toJson());
      final restored = Currency.fromJson(jsonDecode(jsonString));

      expect(restored, currency);
    });

    test('copyWith updates fields', () {
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      final updated = currency.copyWith(
        deleted: true,
        updatedAt: now.add(const Duration(hours: 1)),
      );

      expect(updated.deleted, true);
      expect(updated.updatedAt, isNotNull);
      expect(updated.code, const CurrencyCode('USD')); // unchanged
    });
  });
}
