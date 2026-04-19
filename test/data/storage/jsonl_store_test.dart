import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/storage/jsonl_store.dart';
import 'package:expense_tracker/models/currency.dart';

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

    JsonlStore<Currency> createStore() => JsonlStore<Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
          toJson: (c) => c.toJson(),
          getId: (c) => c.id,
          getUpdatedAt: (c) => c.updatedAt,
          getCreatedAt: (c) => c.createdAt,
        );

    final now = DateTime.utc(2026, 4, 19);

    test('returns empty list for non-existent file', () async {
      final store = createStore();
      final result = await store.readAll();
      expect(result, isEmpty);
    });

    test('appends and reads a single entity', () async {
      final store = createStore();
      final currency = Currency(
        id: 'cur-1',
        code: 'USD',
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      final result = await store.readAll();

      expect(result, hasLength(1));
      expect(result.first.code, 'USD');
    });

    test('appends multiple entities', () async {
      final store = createStore();
      final currencies = [
        Currency(
          id: 'cur-1',
          code: 'USD',
          name: 'US Dollar',
          type: CurrencyType.fiat,
          createdAt: now,
        ),
        Currency(
          id: 'cur-2',
          code: 'EUR',
          name: 'Euro',
          type: CurrencyType.fiat,
          createdAt: now,
        ),
      ];

      await store.appendAll(currencies);
      final result = await store.readAll();

      expect(result, hasLength(2));
    });

    test('keeps latest version when same id is appended', () async {
      final store = createStore();
      final original = Currency(
        id: 'cur-1',
        code: 'USD',
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
      final result = await store.readAll();

      expect(result, hasLength(1));
      expect(result.first.name, 'United States Dollar');
    });

    test('readActive filters deleted entities', () async {
      final store = createStore();
      final active = Currency(
        id: 'cur-1',
        code: 'USD',
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      final deleted = Currency(
        id: 'cur-2',
        code: 'EUR',
        name: 'Euro',
        type: CurrencyType.fiat,
        createdAt: now,
        deleted: true,
      );

      await store.appendAll([active, deleted]);
      final result = await store.readActive((c) => c.deleted);

      expect(result, hasLength(1));
      expect(result.first.code, 'USD');
    });

    test('soft delete by appending with deleted=true', () async {
      final store = createStore();
      final currency = Currency(
        id: 'cur-1',
        code: 'USD',
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      await store.append(currency.copyWith(
        deleted: true,
        updatedAt: now.add(const Duration(hours: 1)),
      ));

      final all = await store.readAll();
      expect(all, hasLength(1));
      expect(all.first.deleted, true);

      final active = await store.readActive((c) => c.deleted);
      expect(active, isEmpty);
    });

    test('writeAll overwrites entire file', () async {
      final store = createStore();

      // Append 3 entities
      for (var i = 0; i < 3; i++) {
        await store.append(Currency(
          id: 'cur-$i',
          code: 'C$i',
          name: 'Currency $i',
          type: CurrencyType.custom,
          createdAt: now,
        ));
      }

      // Overwrite with just 1 entity
      await store.writeAll([
        Currency(
          id: 'cur-new',
          code: 'NEW',
          name: 'New Currency',
          type: CurrencyType.custom,
          createdAt: now,
        ),
      ]);

      final result = await store.readAll();
      expect(result, hasLength(1));
      expect(result.first.code, 'NEW');
    });

    test('handles empty lines gracefully', () async {
      final store = createStore();
      final currency = Currency(
        id: 'cur-1',
        code: 'USD',
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      );

      await store.append(currency);
      // Manually append empty lines
      await File(filePath).writeAsString('\n\n', mode: FileMode.append);

      final result = await store.readAll();
      expect(result, hasLength(1));
    });

    test('creates parent directories if they do not exist', () async {
      final deepPath = '${tempDir.path}/a/b/c/test.jsonl';
      final store = JsonlStore<Currency>(
        filePath: deepPath,
        fromJson: Currency.fromJson,
        toJson: (c) => c.toJson(),
        getId: (c) => c.id,
        getUpdatedAt: (c) => c.updatedAt,
        getCreatedAt: (c) => c.createdAt,
      );

      await store.append(Currency(
        id: 'cur-1',
        code: 'USD',
        name: 'US Dollar',
        type: CurrencyType.fiat,
        createdAt: now,
      ));

      expect(await File(deepPath).exists(), true);
    });
  });
}
