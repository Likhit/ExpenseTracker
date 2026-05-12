import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/storage/jsonl_store.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/ids.dart';

void main() {
  group('JsonlStore', () {
    late Directory tempDir;
    late String filePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('jsonl_test_');
      filePath = '${tempDir.path}/test.jsonl';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    JsonlStore<CurrencyId, Currency> createStore() =>
        JsonlStore<CurrencyId, Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
        );

    final now = DateTime.utc(2026, 4, 19);

    test('yields nothing for non-existent file', () async {
      final store = createStore();
      final result = await store.readReverse().toList();
      expect(result, isEmpty);
    });

    test('appends and reads a single entity', () async {
      final store = createStore();
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      final result = await store.readReverse().toList();

      expect(result, hasLength(1));
      expect(result.first.code, const CurrencyCode('USD'));
    });

    test('appendAll writes multiple entities', () async {
      final store = createStore();
      final currencies = [
        Currency(
          id: const CurrencyId('cur-1'),
          code: const CurrencyCode('USD'),
          name: 'US Dollar',
          type: CurrencyType.fiat,
          createdAt: now,
        ),
        Currency(
          id: const CurrencyId('cur-2'),
          code: const CurrencyCode('EUR'),
          name: 'Euro',
          type: CurrencyType.fiat,
          createdAt: now,
        ),
      ];

      await store.appendAll(currencies);
      final result = await store.readReverse().toList();

      expect(result, hasLength(2));
    });

    test('readReverse yields entities newest-first, no dedup', () async {
      final store = createStore();
      final original = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      final updated = original.copyWith(
        name: 'United States Dollar',
        updatedAt: now.add(const Duration(hours: 1)),
      );

      await store.append(original);
      await store.append(updated);
      final result = await store.readReverse().toList();

      expect(result, hasLength(2));
      expect(result.first.name, 'United States Dollar');
      expect(result.last.name, 'US Dollar');
    });

    test('readReverse includes soft-deleted entries', () async {
      final store = createStore();
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      await store.append(currency.copyWith(
        deleted: true,
        updatedAt: now.add(const Duration(hours: 1)),
      ));

      final all = await store.readReverse().toList();
      expect(all, hasLength(2));
      expect(all.first.deleted, true);
      expect(all.last.deleted, false);
    });

    test('writeAll overwrites entire file', () async {
      final store = createStore();

      for (var i = 0; i < 3; i++) {
        await store.append(Currency(
          id: CurrencyId('cur-$i'),
          code: CurrencyCode('C$i'),
          name: 'Currency $i',
          type: CurrencyType.fiat,
          createdAt: now,
        ));
      }

      await store.writeAll([
        Currency(
          id: const CurrencyId('cur-new'),
          code: const CurrencyCode('NEW'),
          name: 'New Currency',
          type: CurrencyType.fiat,
          createdAt: now,
        ),
      ]);

      final result = await store.readReverse().toList();
      expect(result, hasLength(1));
      expect(result.first.code, const CurrencyCode('NEW'));
    });

    test('handles empty lines gracefully', () async {
      final store = createStore();
      final currency = Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      await File(filePath).writeAsString('\n\n', mode: FileMode.append);

      final result = await store.readReverse().toList();
      expect(result, hasLength(1));
    });

    test('creates parent directories if they do not exist', () async {
      final deepPath = '${tempDir.path}/a/b/c/test.jsonl';
      final store = JsonlStore<CurrencyId, Currency>(
        filePath: deepPath,
        fromJson: Currency.fromJson,
      );

      await store.append(Currency(
        id: const CurrencyId('cur-1'),
        code: const CurrencyCode('USD'),
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      ));

      expect(await File(deepPath).exists(), true);
    });
  });
}
