import 'package:uuid/uuid.dart';

import '../../models/line_id.dart';
import '../storage/jsonl_storable.dart';
import '../storage/jsonl_store.dart';

const _uuid = Uuid();
LineId _newLineId() => LineId.of(_uuid.v4());

/// Read-only view of a repository.
///
/// Exposed by `LedgerService` so external callers can query entities
/// without being able to mutate the underlying store directly. Writes
/// must go through service-level helpers (e.g. `LedgerService.save`)
/// so validation, chain-pointer maintenance, and aggregator updates can
/// be enforced uniformly.
abstract interface class ReadOnlyRepository<Id,
    T extends JsonlStorable<Id>> {
  /// Returns the latest version of every entity. Includes soft-deleted ones.
  Future<List<T>> getAll();
}

/// Base repository over a [JsonlStore]. Dedups by id when reading and
/// maintains a single per-file append-chain on every write.
///
/// The store yields every line in reverse append order (newest first).
/// `getAll` walks that stream, keeping the first occurrence of each id —
/// since newest is first, that's the current state of every entity. The
/// returned list includes soft-deleted entries (deleted: true). Callers
/// who only want active entries should filter.
///
/// On `save`/`saveAll`, the repository generates a fresh `lineId` and
/// sets `prev` to the lineId of the previous append in this file —
/// regardless of which entity id that append touched. Together, every
/// append in a single file forms one linear chain. The lookup uses a
/// lazy in-memory tip cache warmed from the file on first access.
///
/// This class is intended as an internal collaborator of `LedgerService`;
/// production code should not use the write methods directly — go through
/// the service so validation and later-phase hooks (1.8) apply.
class Repository<Id, T extends JsonlStorable<Id>>
    implements ReadOnlyRepository<Id, T> {
  final JsonlStore<Id, T> store;

  /// Most recent `lineId` in the file, or [LineId.first] if the file is
  /// empty. Built lazily on the first read or write, then maintained
  /// incrementally.
  LineId? _tip;
  bool _tipCached = false;

  Repository(this.store);

  Future<LineId> _ensureTip() async {
    if (_tipCached) return _tip ?? const LineId.first();
    LineId? tip;
    await for (final entity in store.readReverse()) {
      // readReverse yields newest-first; the very first entry is the
      // file's current chain tip.
      if (entity.lineId == null) {
        throw StateError(
            'Corrupted repository file: persisted entry has no lineId');
      }
      tip = entity.lineId;
      break;
    }
    _tip = tip;
    _tipCached = true;
    return tip ?? const LineId.first();
  }

  @override
  Future<List<T>> getAll() async {
    final seen = <Id>{};
    final result = <T>[];
    await for (final entity in store.readReverse()) {
      if (seen.add(entity.id)) {
        result.add(entity);
      }
    }
    return result;
  }

  Future<T> save(T entity) async {
    final prev = await _ensureTip();
    final lineId = _newLineId();
    final chained = entity.withChain(lineId: lineId, prev: prev) as T;
    await store.append(chained);
    _tip = lineId;
    return chained;
  }

  Future<List<T>> saveAll(List<T> entities) async {
    if (entities.isEmpty) return const [];
    var prev = await _ensureTip();
    final chained = <T>[];
    for (final entity in entities) {
      final lineId = _newLineId();
      final c = entity.withChain(lineId: lineId, prev: prev) as T;
      chained.add(c);
      prev = lineId;
    }
    await store.appendAll(chained);
    _tip = prev;
    return chained;
  }

  /// Soft-deletes by appending a new chained version with deleted=true.
  Future<T> delete(T entity) =>
      save(entity.withDeleted(DateTime.now()) as T);
}
