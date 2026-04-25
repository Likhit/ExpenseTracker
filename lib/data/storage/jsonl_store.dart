import 'dart:convert';
import 'dart:io';

import 'jsonl_storable.dart';

/// Generic append-only JSONL storage.
///
/// Each line is a JSON object with an `id` field. Edits and deletes append
/// a new line with the same id and a newer timestamp. State is reconstructed
/// by keeping only the latest version of each id.
///
/// **Append-only delete**: Deleting an entity appends a new line with
/// `deleted: true` and the same id. On read, deduplication keeps only the
/// latest version per id, so the deleted version supersedes the original.
/// Both lines remain in the file — this is intentional for sync/merge support.
class JsonlStore<T extends JsonlStorable> {
  final File _file;
  final T Function(Map<String, dynamic>) _fromJson;

  JsonlStore({
    required String filePath,
    required T Function(Map<String, dynamic>) fromJson,
  })  : _file = File(filePath),
        _fromJson = fromJson;

  /// Reads all lines and returns the latest version of each entity.
  Future<List<T>> readAll() async {
    if (!await _file.exists()) return [];

    final lines = await _file.readAsLines();
    final map = <String, T>{};

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      final entity = _fromJson(json);
      final existing = map[entity.id];

      if (existing == null ||
          _effectiveTime(entity).isAfter(_effectiveTime(existing))) {
        map[entity.id] = entity;
      }
    }

    return map.values.toList();
  }

  /// Reads all non-deleted entities.
  Future<List<T>> readActive() async {
    final all = await readAll();
    return all.where((e) => !e.deleted).toList();
  }

  /// Appends a single entity as a new line.
  Future<void> append(T entity) async {
    await _ensureFileExists();
    final json = jsonEncode(entity.toJson());
    await _file.writeAsString('$json\n', mode: FileMode.append);
  }

  /// Appends multiple entities as new lines.
  Future<void> appendAll(List<T> entities) async {
    if (entities.isEmpty) return;
    await _ensureFileExists();
    final buffer = StringBuffer();
    for (final entity in entities) {
      buffer.writeln(jsonEncode(entity.toJson()));
    }
    await _file.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  /// Overwrites the file with only the given entities (used for merge).
  Future<void> writeAll(List<T> entities) async {
    await _ensureFileExists();
    final buffer = StringBuffer();
    for (final entity in entities) {
      buffer.writeln(jsonEncode(entity.toJson()));
    }
    await _file.writeAsString(buffer.toString());
  }

  DateTime _effectiveTime(T entity) => entity.updatedAt ?? entity.createdAt;

  Future<void> _ensureFileExists() async {
    if (!await _file.exists()) {
      await _file.parent.create(recursive: true);
      await _file.create();
    }
  }
}
