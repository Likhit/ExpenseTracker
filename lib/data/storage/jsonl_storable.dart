import '../../models/line_id.dart';

/// Non-generic supertype for everything that can live in a JSONL store.
///
/// Captures the storage-layer contract (timestamps, soft-delete marker,
/// JSON encoding, soft-delete copy, and append-chain pointers) without
/// committing to a specific id type.
abstract class JsonlEntity {
  bool get deleted;
  DateTime get createdAt;
  DateTime? get updatedAt;

  /// Unique id of this specific append. `null` for an in-memory entity
  /// that has never been saved; non-null ([LineId.of]) for any entity
  /// loaded from disk. The repository assigns this on every write.
  LineId? get lineId;

  /// Pointer to the previous append in this repository file (regardless
  /// of entity id). [LineId.first] for the very first append into a
  /// fresh file; [LineId.of] for every subsequent append. Together with
  /// [lineId], all appends in a single file form one linear chain —
  /// Phase 1.9 sync rebases over divergent tips by rewriting this field.
  LineId get prev;

  Map<String, dynamic> toJson();

  /// Returns a copy of this entity with `deleted: true` and the given
  /// `updatedAt`. Used by the repository layer for soft-deletes.
  JsonlEntity withDeleted(DateTime updatedAt);

  /// Returns a copy with the given chain pointers. Assigned by the
  /// repository on every append; callers should not invoke this.
  JsonlEntity withChain({required LineId lineId, required LineId prev});
}

/// Adds a typed id to [JsonlEntity]. The id type is what `JsonlStore`
/// dedups on and what `Repository<Id, T>` is parameterized by.
abstract class JsonlStorable<Id> implements JsonlEntity {
  Id get id;

  @override
  JsonlStorable<Id> withDeleted(DateTime updatedAt);

  @override
  JsonlStorable<Id> withChain({required LineId lineId, required LineId prev});
}
