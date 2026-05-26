import 'package:sembast/sembast.dart';

import '../../models/line_id.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';
import 'ledger_view.dart';

/// Persists each [LedgerView] to a sembast database so views survive restarts
/// without replaying the whole journal.
///
/// Per view name it stores one record:
/// - the view's **config** (`filter`, `groupBy`, `template`) so a restored
///   snapshot can be checked against what the caller now asks for — a view's
///   identity is its name *and* its config, and the two can drift across app
///   versions;
/// - the serialized stats **tree** (rows are not persisted — restored leaves
///   carry a [Checkpoint]);
/// - a **watermark**: the transactions-journal tip [LineId] at snapshot time.
///
/// A snapshot is safe to restore only when both its config matches the
/// requested view and its watermark still equals the journal tip (see
/// `LedgerService.register`).
///
/// The caller owns the [Database] (file-backed in production, in-memory in
/// tests), keeping this layer independent of the sembast factory choice.
class ViewStore {
  final Database _db;
  final _views = stringMapStoreFactory.store('views');

  ViewStore(this._db);

  /// Writes [view]'s config, current tree, and [watermark], replacing any
  /// previous snapshot for its name.
  Future<void> save(LedgerView view, LineId watermark) =>
      _views.record(view.name).put(_db, {
        'watermark': watermark.toJson(),
        'filter': view.filter.toJson(),
        'groupBy': [for (final dim in view.groupBy) dim.toJson()],
        'template': view.template.toJson(),
        'tree': view.result.toJson(),
      });

  /// The persisted snapshot for [name], or null if none was ever written.
  Future<ViewSnapshot?> load(String name) async {
    final record = await _views.record(name).get(_db);
    if (record == null) return null;
    return ViewSnapshot(
      watermark:
          LineId.fromJson((record['watermark'] as Map).cast<String, dynamic>()),
      filter:
          LedgerFilter.fromJson((record['filter'] as Map).cast<String, dynamic>()),
      groupBy: [
        for (final dim in record['groupBy'] as List)
          GroupDimension.fromJson((dim as Map).cast<String, dynamic>()),
      ],
      template:
          Stats.fromJson((record['template'] as Map).cast<String, Object?>()),
      tree: QueryResult.fromJson((record['tree'] as Map).cast<String, Object?>()),
    );
  }
}

/// A view's persisted state: the [filter]/[groupBy]/[template] it was built
/// with, the restored stats [tree], and the journal [watermark] it reflects.
class ViewSnapshot {
  final LineId watermark;
  final LedgerFilter filter;
  final List<GroupDimension> groupBy;
  final Stats template;
  final QueryResult tree;

  ViewSnapshot({
    required this.watermark,
    required this.filter,
    required this.groupBy,
    required this.template,
    required this.tree,
  });
}
