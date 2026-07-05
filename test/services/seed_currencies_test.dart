import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';
import 'package:expense_tracker/services/ledger_service.dart';
import 'package:expense_tracker/services/seed_currencies.dart';

void main() {
  late Directory tempDir;

  Future<LedgerService> freshLedger() => LedgerService.create(
        accountsPath: '${tempDir.path}/accounts.jsonl',
        categoriesPath: '${tempDir.path}/categories.jsonl',
        currenciesPath: '${tempDir.path}/currencies.jsonl',
        transactionsPath: '${tempDir.path}/transactions.jsonl',
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('seed_currencies_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('seeds the default set on an empty ledger', () async {
    final ledger = await freshLedger();

    await seedDefaultCurrenciesIfEmpty(ledger);

    final codes = (await ledger.currencies.getAll())
        .map((c) => c.code.value)
        .toSet();
    expect(codes, containsAll(['USD', 'EUR', 'GBP', 'INR', 'JPY']));
    expect(codes, containsAll(['BTC', 'ETH']));
  });

  test('is a no-op when any currency already exists', () async {
    final ledger = await freshLedger();
    await ledger.save(Currency(
      id: const CurrencyId('user-aud'),
      code: const CurrencyCode('AUD'),
      name: 'Australian Dollar',
      type: CurrencyType.fiat,
      decimalPlaces: 2,
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    await seedDefaultCurrenciesIfEmpty(ledger);

    final codes =
        (await ledger.currencies.getAll()).map((c) => c.code.value).toSet();
    expect(codes, {'AUD'});
  });

  test('respects soft-deletes (does not re-seed cleared lists)', () async {
    final ledger = await freshLedger();
    final usd = Currency(
      id: const CurrencyId('user-usd'),
      code: const CurrencyCode('USD'),
      name: 'US Dollar',
      type: CurrencyType.fiat,
      decimalPlaces: 2,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await ledger.save(usd);
    await ledger.delete(usd);

    await seedDefaultCurrenciesIfEmpty(ledger);

    // The soft-deleted USD is still on disk as the latest version, so seeding
    // sees a non-empty list and skips — the user explicitly cleared it.
    final all = await ledger.currencies.getAll();
    expect(all, hasLength(1));
    expect(all.single.code.value, 'USD');
    expect(all.single.deleted, true);
  });
}
