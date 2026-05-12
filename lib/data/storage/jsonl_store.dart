import 'dart:convert';
import 'dart:io';

import 'jsonl_storable.dart';

/// Generic append-only JSONL storage.
///
/// Each line is a JSON object. Edits and deletes append a new line with
/// the same id and a newer timestamp. The store yields raw lines — it
/// does not deduplicate by id, does not filter deleted entries, and does
/// not attempt to reconstruct logical state. Those concerns belong to
/// the [Repository] layer (dedup) and the caller (filtering deletes).
class JsonlStore<Id, T extends JsonlStorable<Id>> {
  final File _file;
  final T Function(Map<String, dynamic>) _fromJson;

  JsonlStore({
    required String filePath,
    required T Function(Map<String, dynamic>) fromJson,
  })  : _file = File(filePath),
        _fromJson = fromJson;

  /// Streams entities in reverse append order (most recently written first).
  ///
  /// Yields every line as-is — no dedup, no deleted-filtering. Callers can
  /// `.take(n)` / `.firstWhere(...)` for partial reads.
  ///
  /// TODO: current implementation loads the whole file then yields reversed
  /// for simplicity. Swap to chunked seek-from-EOF for true laziness when
  /// transaction files grow large.
  Stream<T> readReverse() async* {
    if (!await _file.exists()) return;
    final lines = await _file.readAsLines();
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;
      yield _fromJson(json);
    }
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

  Future<void> _ensureFileExists() async {
    if (!await _file.exists()) {
      await _file.parent.create(recursive: true);
      await _file.create();
    }
  }
}
