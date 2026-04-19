import 'dart:convert';
import 'dart:io';

/// Generic append-only JSONL storage.
///
/// Each line is a JSON object with an `id` field. Edits and deletes append
/// a new line with the same id and a newer timestamp. State is reconstructed
/// by keeping only the latest version of each id.
class JsonlStore<T> {
  final File _file;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;
  final String Function(T) _getId;
  final DateTime? Function(T) _getUpdatedAt;
  final DateTime Function(T) _getCreatedAt;

  JsonlStore({
    required String filePath,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required String Function(T) getId,
    required DateTime? Function(T) getUpdatedAt,
    required DateTime Function(T) getCreatedAt,
  })  : _file = File(filePath),
        _fromJson = fromJson,
        _toJson = toJson,
        _getId = getId,
        _getUpdatedAt = getUpdatedAt,
        _getCreatedAt = getCreatedAt;

  /// Reads all lines and returns the latest version of each entity.
  Future<List<T>> readAll() async {
    if (!await _file.exists()) return [];

    final lines = await _file.readAsLines();
    final map = <String, T>{};

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      final entity = _fromJson(json);
      final id = _getId(entity);
      final existing = map[id];

      if (existing == null || _isNewer(entity, existing)) {
        map[id] = entity;
      }
    }

    return map.values.toList();
  }

  /// Reads all non-deleted entities.
  Future<List<T>> readActive(bool Function(T) isDeleted) async {
    final all = await readAll();
    return all.where((e) => !isDeleted(e)).toList();
  }

  /// Appends a single entity as a new line.
  Future<void> append(T entity) async {
    await _ensureFileExists();
    final json = jsonEncode(_toJson(entity));
    await _file.writeAsString('$json\n', mode: FileMode.append);
  }

  /// Appends multiple entities as new lines.
  Future<void> appendAll(List<T> entities) async {
    if (entities.isEmpty) return;
    await _ensureFileExists();
    final buffer = StringBuffer();
    for (final entity in entities) {
      buffer.writeln(jsonEncode(_toJson(entity)));
    }
    await _file.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  /// Overwrites the file with only the given entities (used for merge).
  Future<void> writeAll(List<T> entities) async {
    await _ensureFileExists();
    final buffer = StringBuffer();
    for (final entity in entities) {
      buffer.writeln(jsonEncode(_toJson(entity)));
    }
    await _file.writeAsString(buffer.toString());
  }

  bool _isNewer(T candidate, T existing) {
    final candidateTime =
        _getUpdatedAt(candidate) ?? _getCreatedAt(candidate);
    final existingTime =
        _getUpdatedAt(existing) ?? _getCreatedAt(existing);
    return candidateTime.isAfter(existingTime);
  }

  Future<void> _ensureFileExists() async {
    if (!await _file.exists()) {
      await _file.parent.create(recursive: true);
      await _file.create();
    }
  }
}
