import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/repositories/account_repository.dart';
import 'package:expense_tracker/models/account.dart';

void main() {
  group('AccountRepository', () {
    late Directory tempDir;
    late AccountRepository repo;
    final now = DateTime.utc(2026, 4, 19);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('account_repo_test_');
      repo = AccountRepository(filePath: '${tempDir.path}/accounts.jsonl');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save and retrieve accounts', () async {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Checking',
        type: AccountType.asset,
        createdAt: now,
      );

      await repo.save(account);
      final accounts = await repo.getAll();

      expect(accounts, hasLength(1));
      expect(accounts.first.path, 'Chase::Checking');
    });

    test('save multiple accounts', () async {
      await repo.saveAll([
        Account(
          id: 'acc-1',
          path: 'Chase::Checking',
          type: AccountType.asset,
          createdAt: now,
        ),
        Account(
          id: 'acc-2',
          path: 'Fidelity::401k',
          type: AccountType.asset,
          createdAt: now,
        ),
      ]);

      final accounts = await repo.getAll();
      expect(accounts, hasLength(2));
    });

    test('delete removes account from active list', () async {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Checking',
        type: AccountType.asset,
        createdAt: now,
      );

      await repo.save(account);
      await repo.delete(account);

      final accounts = await repo.getAll();
      expect(accounts, isEmpty);
    });

    test('update account by saving with same id', () async {
      final account = Account(
        id: 'acc-1',
        path: 'Chase::Checking',
        type: AccountType.asset,
        createdAt: now,
      );

      await repo.save(account);
      await repo.save(account.copyWith(
        notes: 'Primary account',
        updatedAt: now.add(const Duration(hours: 1)),
      ));

      final accounts = await repo.getAll();
      expect(accounts, hasLength(1));
      expect(accounts.first.notes, 'Primary account');
    });
  });
}
