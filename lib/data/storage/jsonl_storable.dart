/// Non-generic supertype for everything that can live in a JSONL store.
///
/// Captures the storage-layer contract (timestamps, soft-delete marker,
/// JSON encoding, and a copy-with-deleted constructor) without committing
/// to a specific id type. `LedgerService.save` uses this as its bound so
/// a single generic method can dispatch over every model.
abstract class JsonlEntity {
  bool get deleted;
  DateTime get createdAt;
  DateTime? get updatedAt;

  Map<String, dynamic> toJson();

  /// Returns a copy of this entity with `deleted: true` and the given
  /// `updatedAt`. Used by the repository layer for soft-deletes.
  JsonlEntity withDeleted(DateTime updatedAt);
}

/// Adds a typed id to [JsonlEntity]. The id type is what `JsonlStore`
/// dedups on and what `Repository<Id, T>` is parameterized by.
abstract class JsonlStorable<Id> implements JsonlEntity {
  Id get id;

  @override
  JsonlStorable<Id> withDeleted(DateTime updatedAt);
}
