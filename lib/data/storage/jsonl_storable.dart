/// Interface for models that can be stored in JSONL files.
///
/// All models stored via [JsonlStore] must implement this interface,
/// providing their id, timestamps, and a copy with `deleted: true` for
/// soft-deletes.
abstract class JsonlStorable<Id> {
  Id get id;
  DateTime get createdAt;
  DateTime? get updatedAt;
  bool get deleted;

  Map<String, dynamic> toJson();

  /// Returns a copy of this entity with `deleted: true` and the given
  /// `updatedAt`. Used by the repository layer for soft-deletes.
  JsonlStorable<Id> withDeleted(DateTime updatedAt);
}
