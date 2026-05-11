/// Interface for models that can be stored in JSONL files.
///
/// All models stored via [JsonlStore] must implement this interface,
/// providing their ID and timestamps for deduplication.
abstract class JsonlStorable {
  String get id;
  DateTime get createdAt;
  DateTime? get updatedAt;
  bool get deleted;

  Map<String, dynamic> toJson();
}
