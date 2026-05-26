import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/repositories/repository.dart';
import 'package:expense_tracker/data/storage/jsonl_store.dart';

import 'test_entity.dart';

void main() {
  group('Repository', () {
    late Directory tempDir;
    late String filePath;
    late Repository<TestId, TestEntity> repo;
    final now = DateTime.utc(2026, 4, 19);

    TestEntity entity({String id = 'e-1', String value = 'v1'}) => TestEntity(
          id: TestId(id),
          value: value,
          createdAt: now,
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repository_test_');
      filePath = '${tempDir.path}/test.jsonl';
      repo = Repository<TestId, TestEntity>(
        JsonlStore<TestId, TestEntity>(
          filePath: filePath,
          fromJson: TestEntity.fromJson,
        ),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save and retrieve entity', () async {
      await repo.save(entity());
      final all = await repo.getAll();

      expect(all, hasLength(1));
      expect(all.first.value, 'v1');
    });

    test('delete marks entity as deleted (latest version)', () async {
      await repo.save(entity());
      await repo.delete(entity());

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.deleted, isTrue);

      final active = all.where((e) => !e.deleted).toList();
      expect(active, isEmpty);
    });

    test('updating an entity keeps only the latest version per id', () async {
      await repo.save(entity());
      await repo.save(entity().copyWith(value: 'renamed'));

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.value, 'renamed');
    });
  });
}
