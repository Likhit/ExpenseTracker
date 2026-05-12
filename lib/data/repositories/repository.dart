import 'package:uuid/uuid.dart';

import '../storage/jsonl_storable.dart';
import '../storage/jsonl_store.dart';

const _uuid = Uuid();
String _newLineId() => _uuid.v4();

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
/// maintains a per-entity append-chain on every write.
///
/// The store yields every line in reverse append order (newest first).
/// `getAll` walks that stream, keeping the first occurrence of each id —
/// since newest is first, that's the current state of every entity. The
/// returned list includes soft-deleted entries (deleted: true). Callers
/// who only want active entries should filter.
///
/// On `save`/`saveAll`, the repository generates a fresh `lineId` and
/// sets `prev` to the lineId of the previous version of the same entity
/// (or `null` if this is the first version). The lookup uses a lazy
/// in-memory cache warmed from the file on first access.
///
/// This class is intended as an internal collaborator of `LedgerService`;
/// production code should not use the write methods directly — go through
/// the service so validation and later-phase hooks (1.8) apply.
class Repository<Id, T extends JsonlStorable<Id>>
    implements ReadOnlyRepository<Id, T> {
  final JsonlStore<Id, T> store;

  /// Per-entity cache of the most recent `lineId`. Built lazily on the
  /// first read or write, then maintained incrementally.
  Map<Id, String>? _lineIdCache;

  Repository(this.store);

  Future<Map<Id, String>> _ensureCache() async {
    if (_lineIdCache != null) return _lineIdCache!;
    final cache = <Id, String>{};
    await for (final entity in store.readReverse()) {
      // readReverse yields newest-first; first sighting of an id is the
      // current chain tip.
      if (entity.lineId == null) continue;
      cache.putIfAbsent(entity.id, () => entity.lineId!);
    }
    _lineIdCache = cache;
    return cache;
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
    final cache = await _ensureCache();
    final prev = cache[entity.id];
    final lineId = _newLineId();
    final chained = entity.withChain(lineId: lineId, prev: prev) as T;
    await store.append(chained);
    cache[entity.id] = lineId;
    return chained;
  }

  Future<List<T>> saveAll(List<T> entities) async {
    if (entities.isEmpty) return const [];
    final cache = await _ensureCache();
    final chained = <T>[];
    for (final entity in entities) {
      final prev = cache[entity.id];
      final lineId = _newLineId();
      final c = entity.withChain(lineId: lineId, prev: prev) as T;
      chained.add(c);
      cache[entity.id] = lineId;
    }
    await store.appendAll(chained);
    return chained;
  }

  /// Soft-deletes by appending a new chained version with deleted=true.
  Future<T> delete(T entity) =>
      save(entity.withDeleted(DateTime.now()) as T);

  /// Idempotent migration: assigns `lineId` and `prev` to any persisted
  /// entries that pre-date the chain-pointer scheme. Walks the file in
  /// append order, assigns a UUID to each unchained line, and rewrites
  /// the file in one pass. Returns the number of entries that were
  /// assigned new lineIds (0 if the file was already migrated).
  Future<int> migrate() async {
    final reverseList = <T>[];
    await for (final entity in store.readReverse()) {
      reverseList.add(entity);
    }
    if (reverseList.isEmpty) return 0;
    final forward = reverseList.reversed.toList();

    final cache = <Id, String>{};
    final result = <T>[];
    var assigned = 0;
    for (final entity in forward) {
      if (entity.lineId != null) {
        cache[entity.id] = entity.lineId!;
        result.add(entity);
        continue;
      }
      final prev = cache[entity.id];
      final lineId = _newLineId();
      result.add(entity.withChain(lineId: lineId, prev: prev) as T);
      cache[entity.id] = lineId;
      assigned++;
    }
    if (assigned == 0) {
      _lineIdCache = cache;
      return 0;
    }
    await store.writeAll(result);
    _lineIdCache = cache;
    return assigned;
  }
}
