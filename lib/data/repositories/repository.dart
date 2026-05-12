import '../storage/jsonl_storable.dart';
import '../storage/jsonl_store.dart';

/// Read-only view of a repository.
///
/// Exposed by `LedgerService` so external callers can query entities
/// without being able to mutate the underlying store directly. Writes
/// must go through service-level helpers (e.g. `LedgerService.saveAccount`)
/// so validation, chain-pointer maintenance, and aggregator updates can
/// be enforced uniformly.
abstract interface class ReadOnlyRepository<Id,
    T extends JsonlStorable<Id>> {
  /// Returns the latest version of every entity. Includes soft-deleted ones.
  Future<List<T>> getAll();
}

/// Base repository over a [JsonlStore]. Dedups by id when reading.
///
/// The store yields every line in reverse append order (newest first).
/// `getAll` walks that stream, keeping the first occurrence of each id —
/// since newest is first, that's the current state of every entity. The
/// returned list includes soft-deleted entries (deleted: true). Callers
/// who only want active entries should filter.
///
/// This class is intended as an internal collaborator of `LedgerService`;
/// production code should not use the write methods directly — go through
/// the service so validation and later-phase hooks (1.6/1.8) apply.
class Repository<Id, T extends JsonlStorable<Id>>
    implements ReadOnlyRepository<Id, T> {
  final JsonlStore<Id, T> store;

  Repository(this.store);

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

  Future<void> save(T entity) => store.append(entity);

  Future<void> saveAll(List<T> entities) => store.appendAll(entities);

  /// Soft-deletes by appending a new version with deleted=true.
  Future<void> delete(T entity) =>
      store.append(entity.withDeleted(DateTime.now()) as T);
}
