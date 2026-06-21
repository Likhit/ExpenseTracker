import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/data/storage/file_sync.dart';
import 'package:expense_tracker/models/line_id.dart';

import '../repositories/test_entity.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);

  // Builds a chained entity. [line] is this append's lineId; [prev] the one
  // before it in the file.
  TestEntity e(
    String id,
    String value, {
    required String line,
    required LineId prev,
  }) =>
      TestEntity(
        id: TestId(id),
        value: value,
        createdAt: now,
        lineId: LineId.of(line),
        prev: prev,
      );

  // Builds a linear chain from (id, value, lineId) triples: each append's prev
  // is the previous append's lineId (first is LineId.first).
  List<TestEntity> chain(List<(String, String, String)> entries) {
    final out = <TestEntity>[];
    LineId prev = const LineId.first();
    for (final (id, value, line) in entries) {
      out.add(e(id, value, line: line, prev: prev));
      prev = LineId.of(line);
    }
    return out;
  }

  // Asserts [c] is a single linear chain: first prev is LineId.first, each
  // subsequent prev points to the preceding lineId.
  void expectLinear(List<TestEntity> c) {
    expect(c.first.prev, const LineId.first());
    for (var i = 1; i < c.length; i++) {
      expect(c[i].prev, c[i - 1].lineId,
          reason: 'append $i should chain onto append ${i - 1}');
    }
  }

  group('mergeChains — no divergence', () {
    test('identical chains merge to themselves with no conflicts', () {
      final ours = chain([('a', 'a1', 'l1'), ('b', 'b1', 'l2')]);
      final theirs = chain([('a', 'a1', 'l1'), ('b', 'b1', 'l2')]);

      final result = mergeChains(ours, theirs);
      expect(result.conflicts, isEmpty);
      expect(result.merged.map((x) => x.lineId), [LineId.of('l1'), LineId.of('l2')]);
      expectLinear(result.merged);
    });

    test('empty theirs leaves ours untouched', () {
      final ours = chain([('a', 'a1', 'l1')]);
      final result = mergeChains(ours, <TestEntity>[]);
      expect(result.conflicts, isEmpty);
      expect(result.merged, ours);
    });

    test('empty ours adopts theirs', () {
      final theirs = chain([('a', 'a1', 'l1'), ('b', 'b1', 'l2')]);
      final result = mergeChains(<TestEntity>[], theirs);
      expect(result.conflicts, isEmpty);
      expect(result.merged.map((x) => x.id.value), ['a', 'b']);
      expectLinear(result.merged);
    });
  });

  group('mergeChains — clean divergence (no shared entities)', () {
    test('rebases their suffix onto our tip, rewriting prev', () {
      // Shared prefix: l1. Ours adds l2 (entity b); theirs adds l3 (entity c).
      final ours = chain([('a', 'a1', 'l1'), ('b', 'b1', 'l2')]);
      final theirs = chain([('a', 'a1', 'l1'), ('c', 'c1', 'l3')]);

      final result = mergeChains(ours, theirs);
      expect(result.conflicts, isEmpty);
      // Order: prefix (l1), ours (l2), theirs rebased (l3).
      expect(result.merged.map((x) => x.lineId),
          [LineId.of('l1'), LineId.of('l2'), LineId.of('l3')]);
      expectLinear(result.merged);
      // Their append keeps its lineId but now chains onto our tip.
      expect(result.merged.last.lineId, LineId.of('l3'));
      expect(result.merged.last.prev, LineId.of('l2'));
    });

    test('their suffix chains onto the shared tip when ours has no suffix', () {
      final ours = chain([('a', 'a1', 'l1')]);
      final theirs = chain([('a', 'a1', 'l1'), ('c', 'c1', 'l3')]);

      final result = mergeChains(ours, theirs);
      expect(result.conflicts, isEmpty);
      expect(result.merged.map((x) => x.lineId), [LineId.of('l1'), LineId.of('l3')]);
      expect(result.merged.last.prev, LineId.of('l1'));
      expectLinear(result.merged);
    });
  });

  group('mergeChains — conflicts', () {
    test('same entity edited on both sides is surfaced; both versions kept',
        () {
      // Shared prefix l1 (entity a). Both sides then re-edit entity a.
      final ours = chain([('a', 'a1', 'l1'), ('a', 'ours', 'l2')]);
      final theirs = chain([('a', 'a1', 'l1'), ('a', 'theirs', 'l3')]);

      final result = mergeChains(ours, theirs);

      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.id, const TestId('a'));
      expect(conflict.ours.value, 'ours');
      expect(conflict.theirs.value, 'theirs');

      // Both edits remain in the linearized chain (append-only, no loss).
      expect(result.merged.map((x) => x.value), ['a1', 'ours', 'theirs']);
      expectLinear(result.merged);
    });

    test('reports the latest version per conflicting id, once', () {
      final ours = chain([
        ('a', 'a1', 'l1'),
        ('a', 'ours-1', 'l2'),
        ('a', 'ours-2', 'l3'),
      ]);
      final theirs = chain([
        ('a', 'a1', 'l1'),
        ('a', 'theirs-1', 'l4'),
        ('a', 'theirs-2', 'l5'),
      ]);

      final result = mergeChains(ours, theirs);
      expect(result.conflicts, hasLength(1));
      expect(result.conflicts.single.ours.value, 'ours-2');
      expect(result.conflicts.single.theirs.value, 'theirs-2');
      expectLinear(result.merged);
    });

    test('mixes a conflicting and a clean entity', () {
      // Both edit a (conflict); theirs also adds c (clean).
      final ours = chain([('a', 'a1', 'l1'), ('a', 'ours', 'l2')]);
      final theirs = chain([('a', 'a1', 'l1'), ('a', 'theirs', 'l3'), ('c', 'c1', 'l4')]);

      final result = mergeChains(ours, theirs);
      expect(result.conflicts.map((c) => c.id), [const TestId('a')]);
      expect(result.merged.map((x) => x.lineId),
          [LineId.of('l1'), LineId.of('l2'), LineId.of('l3'), LineId.of('l4')]);
      expectLinear(result.merged);
    });
  });
}
