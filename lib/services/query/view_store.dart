import 'package:sembast/sembast.dart';

import '../../models/line_id.dart';
import 'ledger_stats.dart';

/// Persists each [LedgerView]'s maintained tree to a sembast database so views
/// survive restarts without replaying the whole journal.
///
/// Per view name it stores one record: the serialized [QueryResult] stats tree
/// (rows are not persisted — restored leaves carry a [Checkpoint]) plus a
/// `watermark` — the transactions-journal tip [LineId] at the moment the
/// snapshot was taken. On startup a view is restored only if its watermark
/// still matches the journal tip; otherwise it is recomputed.
///
/// The caller owns the [Database] (file-backed in production, in-memory in
/// tests), keeping this layer independent of the sembast factory choice.
class ViewStore {
  final Database _db;
  final _views = stringMapStoreFactory.store('views');

  ViewStore(this._db);

  /// Writes [tree] and [watermark] for the view named [name], replacing any
  /// previous snapshot.
  Future<void> save(String name, QueryResult tree, LineId watermark) =>
      _views.record(name).put(_db, {
        'watermark': watermark.toJson(),
        'tree': tree.toJson(),
      });

  /// The persisted snapshot for [name], or null if none was ever written.
  Future<ViewSnapshot?> load(String name) async {
    final record = await _views.record(name).get(_db);
    if (record == null) return null;
    return ViewSnapshot(
      tree: QueryResult.fromJson((record['tree'] as Map).cast<String, Object?>()),
      watermark:
          LineId.fromJson((record['watermark'] as Map).cast<String, dynamic>()),
    );
  }
}

/// A view's persisted state: its restored stats [tree] and the journal
/// [watermark] it reflects.
class ViewSnapshot {
  final QueryResult tree;
  final LineId watermark;

  ViewSnapshot({required this.tree, required this.watermark});
}
