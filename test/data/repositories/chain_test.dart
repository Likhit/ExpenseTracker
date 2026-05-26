import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/repositories/repository.dart';
import 'package:expense_tracker/data/storage/jsonl_store.dart';
import 'package:expense_tracker/models/line_id.dart';

import 'test_entity.dart';

void main() {
  group('Repository chain pointers', () {
    late Directory tempDir;
    late String filePath;
    final now = DateTime.utc(2026, 4, 19);

    Repository<TestId, TestEntity> newRepo() => Repository<TestId, TestEntity>(
          JsonlStore<TestId, TestEntity>(
            filePath: filePath,
            fromJson: TestEntity.fromJson,
          ),
        );

    TestEntity entity({String id = 'e-1', String value = 'v1'}) => TestEntity(
          id: TestId(id),
          value: value,
          createdAt: now,
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chain_test_');
      filePath = '${tempDir.path}/test.jsonl';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('first save assigns lineId and prev is First', () async {
      final repo = newRepo();
      final saved = await repo.save(entity());

      expect(saved.lineId, isA<Of>());
      expect(saved.prev, const LineId.first());

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.lineId, saved.lineId);
      expect(all.first.prev, const LineId.first());
    });

    test('second save chains onto the previous append', () async {
      final repo = newRepo();
      final first = await repo.save(entity());
      final second = await repo.save(entity().copyWith(value: 'renamed'));

      expect(second.prev, first.lineId);
      expect(second.lineId, isNot(equals(first.lineId)));

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.value, 'renamed');
      expect(all.first.prev, first.lineId);
    });

    test('chain is per-file: different entity ids share one chain',
        () async {
      final repo = newRepo();
      final a = await repo.save(entity(id: 'e-1'));
      final b = await repo.save(entity(id: 'e-2'));
      final c = await repo.save(entity(id: 'e-1', value: 'updated'));

      expect(a.prev, const LineId.first());
      expect(b.prev, a.lineId);
      expect(c.prev, b.lineId);
    });

    test('delete chains as another version', () async {
      final repo = newRepo();
      final first = await repo.save(entity());
      final deleted = await repo.delete(entity());

      expect(deleted.prev, first.lineId);
      expect(deleted.deleted, isTrue);

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.first.deleted, isTrue);
    });

    test('chain survives across repository instances', () async {
      final saved1 = await newRepo().save(entity());
      final saved2 = await newRepo().save(entity().copyWith(value: 'second'));

      expect(saved2.prev, saved1.lineId);
    });

    test('throws when a persisted entry is missing lineId', () async {
      // Corrupt the file by writing a row that omits lineId.
      await File(filePath).writeAsString(
        '${jsonEncode({
              'id': 'e-1',
              'value': 'v1',
              'createdAt': now.toIso8601String(),
              'deleted': false,
              'prev': const LineId.first().toJson(),
            })}\n',
      );

      final repo = newRepo();
      await expectLater(repo.save(entity()), throwsStateError);
    });
  });
}
