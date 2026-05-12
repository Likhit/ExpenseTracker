/// Non-generic supertype for everything that can live in a JSONL store.
///
/// Captures the storage-layer contract (timestamps, soft-delete marker,
/// JSON encoding, soft-delete copy, and per-entity append-chain
/// pointers) without committing to a specific id type.
abstract class JsonlEntity {
  bool get deleted;
  DateTime get createdAt;
  DateTime? get updatedAt;

  /// Unique id of this specific append (one per persisted version).
  /// `null` for an in-memory entity that has never been saved.
  String? get lineId;

  /// `lineId` of the previous persisted version of the same entity.
  /// `null` for the first version of an entity. Together, `lineId` and
  /// `prev` form a per-entity linked-list of edits, which Phase 1.9
  /// (sync) walks during conflict resolution.
  String? get prev;

  Map<String, dynamic> toJson();

  /// Returns a copy of this entity with `deleted: true` and the given
  /// `updatedAt`. Used by the repository layer for soft-deletes.
  JsonlEntity withDeleted(DateTime updatedAt);

  /// Returns a copy with the given chain pointers. Assigned by the
  /// repository on every append; callers should not invoke this.
  JsonlEntity withChain({required String lineId, required String? prev});
}

/// Adds a typed id to [JsonlEntity]. The id type is what `JsonlStore`
/// dedups on and what `Repository<Id, T>` is parameterized by.
abstract class JsonlStorable<Id> implements JsonlEntity {
  Id get id;

  @override
  JsonlStorable<Id> withDeleted(DateTime updatedAt);

  @override
  JsonlStorable<Id> withChain({required String lineId, required String? prev});
}
