import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/repositories/account_repository.dart';
import 'package:expense_tracker/models/account.dart';
import 'package:expense_tracker/models/ids.dart';

void main() {
  group('chain pointers', () {
    late Directory tempDir;
    late String filePath;
    final now = DateTime.utc(2026, 4, 19);

    Account account({String id = 'acc-1', String path = 'Chase::Checking'}) =>
        Account(
          id: AccountId(id),
          path: path,
          type: AccountType.asset,
          createdAt: now,
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chain_test_');
      filePath = '${tempDir.path}/accounts.jsonl';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('first save assigns lineId, prev is null', () async {
      final repo = AccountRepository(filePath: filePath);
      await repo.save(account());

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.lineId, isNotNull);
      expect(all.first.prev, isNull);
    });

    test('second save of same entity sets prev = first lineId', () async {
      final repo = AccountRepository(filePath: filePath);
      await repo.save(account());
      await repo.save(account().copyWith(notes: 'renamed'));

      final lines = await File(filePath).readAsLines();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines[0]) as Map<String, dynamic>;
      final second = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(second['prev'], first['lineId']);
      expect(second['lineId'], isNotNull);
      expect(second['lineId'], isNot(equals(first['lineId'])));
    });

    test('save of different entities are independent chains', () async {
      final repo = AccountRepository(filePath: filePath);
      await repo.save(account(id: 'acc-1'));
      await repo.save(account(id: 'acc-2'));
      await repo.save(account(id: 'acc-1', path: 'Chase::Savings'));

      final lines = await File(filePath).readAsLines();
      expect(lines, hasLength(3));
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      final l3 = jsonDecode(lines[2]) as Map<String, dynamic>;

      expect(l1['prev'], isNull); // acc-1 v1: first
      expect(l2['prev'], isNull); // acc-2 v1: first for its id
      expect(l3['prev'], l1['lineId']); // acc-1 v2: chains over acc-1 v1
    });

    test('saveAll chains correctly within the batch', () async {
      final repo = AccountRepository(filePath: filePath);
      await repo.saveAll([
        account(id: 'acc-1'),
        account(id: 'acc-1', path: 'Chase::Savings'),
        account(id: 'acc-2'),
      ]);

      final lines = await File(filePath).readAsLines();
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      final l3 = jsonDecode(lines[2]) as Map<String, dynamic>;

      expect(l1['prev'], isNull);
      expect(l2['prev'], l1['lineId']); // chains within batch
      expect(l3['prev'], isNull); // different entity
    });

    test('delete chains as another version', () async {
      final repo = AccountRepository(filePath: filePath);
      await repo.save(account());
      await repo.delete(account());

      final lines = await File(filePath).readAsLines();
      expect(lines, hasLength(2));
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(l2['prev'], l1['lineId']);
      expect(l2['deleted'], true);
    });

    test('chain survives across repository instances', () async {
      final repo1 = AccountRepository(filePath: filePath);
      await repo1.save(account());

      final repo2 = AccountRepository(filePath: filePath);
      await repo2.save(account().copyWith(notes: 'after-reopen'));

      final lines = await File(filePath).readAsLines();
      expect(lines, hasLength(2));
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(l2['prev'], l1['lineId']);
    });
  });

  group('migrate', () {
    late Directory tempDir;
    late String filePath;
    final now = DateTime.utc(2026, 4, 19);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chain_migrate_test_');
      filePath = '${tempDir.path}/accounts.jsonl';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> writeLegacyFile(List<Map<String, dynamic>> lines) async {
      final buffer = StringBuffer();
      for (final l in lines) {
        buffer.writeln(jsonEncode(l));
      }
      await File(filePath).writeAsString(buffer.toString());
    }

    Map<String, dynamic> legacyAccount({
      required String id,
      required String path,
      DateTime? updatedAt,
      bool deleted = false,
    }) =>
        {
          'id': id,
          'path': path,
          'type': 'asset',
          'isVirtual': false,
          'createdAt': now.toIso8601String(),
          'updatedAt': updatedAt?.toIso8601String(),
          'deleted': deleted,
        };

    test('assigns chain pointers to legacy entries', () async {
      await writeLegacyFile([
        legacyAccount(id: 'acc-1', path: 'Chase::Checking'),
        legacyAccount(id: 'acc-2', path: 'Fidelity::401k'),
        legacyAccount(
          id: 'acc-1',
          path: 'Chase::Checking',
          updatedAt: now.add(const Duration(hours: 1)),
        ),
      ]);

      final repo = AccountRepository(filePath: filePath);
      final assigned = await repo.migrate();
      expect(assigned, 3);

      final lines = await File(filePath).readAsLines();
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      final l3 = jsonDecode(lines[2]) as Map<String, dynamic>;

      expect(l1['lineId'], isNotNull);
      expect(l1['prev'], isNull);
      expect(l2['lineId'], isNotNull);
      expect(l2['prev'], isNull); // different id, first for it
      expect(l3['prev'], l1['lineId']); // acc-1 second version chains
    });

    test('is idempotent', () async {
      await writeLegacyFile([
        legacyAccount(id: 'acc-1', path: 'Chase::Checking'),
      ]);

      final repo = AccountRepository(filePath: filePath);
      final first = await repo.migrate();
      expect(first, 1);

      final second = await repo.migrate();
      expect(second, 0);
    });

    test('preserves existing chains on a partially-migrated file',
        () async {
      // Hand-crafted: first entry already has chain pointers, second
      // entry is legacy. After migrate(), the second should be chained
      // onto the first.
      await writeLegacyFile([
        {
          ...legacyAccount(id: 'acc-1', path: 'Chase::Checking'),
          'lineId': 'fixed-line-1',
          'prev': null,
        },
        legacyAccount(
          id: 'acc-1',
          path: 'Chase::Savings',
          updatedAt: now.add(const Duration(hours: 1)),
        ),
      ]);

      final repo = AccountRepository(filePath: filePath);
      final assigned = await repo.migrate();
      expect(assigned, 1);

      final lines = await File(filePath).readAsLines();
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(l1['lineId'], 'fixed-line-1');
      expect(l2['prev'], 'fixed-line-1');
    });

    test('next save after migrate chains onto the migrated tip', () async {
      await writeLegacyFile([
        legacyAccount(id: 'acc-1', path: 'Chase::Checking'),
      ]);

      final repo = AccountRepository(filePath: filePath);
      await repo.migrate();
      await repo.save(Account(
        id: const AccountId('acc-1'),
        path: 'Chase::Checking',
        type: AccountType.asset,
        notes: 'note',
        createdAt: now,
      ));

      final lines = await File(filePath).readAsLines();
      expect(lines, hasLength(2));
      final l1 = jsonDecode(lines[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(l2['prev'], l1['lineId']);
    });
  });
}
