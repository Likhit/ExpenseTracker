import '../storage/jsonl_storable.dart';
import '../storage/jsonl_store.dart';

/// Base repository over a [JsonlStore]. Dedups by id when reading.
///
/// The store yields every line in reverse append order (newest first).
/// `getAll` walks that stream, keeping the first occurrence of each id —
/// since newest is first, that's the current state of every entity. The
/// returned list includes soft-deleted entries (deleted: true). Callers
/// who only want active entries should filter.
class Repository<Id, T extends JsonlStorable<Id>> {
  final JsonlStore<Id, T> store;

  Repository(this.store);

  /// Returns the latest version of every entity. Includes soft-deleted ones.
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
