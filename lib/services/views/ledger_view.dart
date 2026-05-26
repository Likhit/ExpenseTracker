import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import '../query/ledger_filter.dart';
import '../query/ledger_group.dart';
import '../query/ledger_stats.dart';
import '../query/transaction_source.dart';

/// A named, kept-fresh aggregation over the journal — conceptually just a
/// (filter, groupBy, stats template) plus the [QueryResult] it maintains.
///
/// Register one via `LedgerService.register(...)` and read its current tree
/// via `ledger.viewResult(name)!.result`. The service feeds every save into
/// [applySave], which updates the maintained tree incrementally, so reads
/// never re-scan the journal.
///
/// The maintained tree is the same shape `LedgerService.query` returns, and
/// is maintained the same way the engine aggregates: a node's stats are the
/// fold of every leg beneath it. A save walks the root→leaf path of each of
/// its legs and `apply`s the leg to every node on the way down — no rebuild,
/// no roll-up pass. An edit/delete first re-applies the *old* version's legs
/// with `deleted` flipped (the [Stat] convention turns that into a subtract),
/// then applies the new version's.
///
/// Leaves expose transactions through a [TransactionSource]; for an in-memory
/// view those are always materialized, but the type leaves room for PR C's
/// disk-restored views to hold an unhydrated [Checkpoint] with live edits
/// stacked on top.
class LedgerView {
  final String name;
  final LedgerFilter filter;
  final List<GroupDimension> groupBy;

  /// Empty-state template fixing which [Stat] kinds every node tracks.
  final Stats template;

  /// Root of the maintained tree (key [GroupKey.none]). Its stats are the
  /// running total across the whole view; children partition it along
  /// [groupBy], one tree level per dimension.
  final _Node _root;

  /// Memoized immutable snapshot, invalidated on every mutation.
  QueryResult? _cached;

  LedgerView({
    required String name,
    LedgerFilter? filter,
    List<GroupDimension>? groupBy,
    Stats? template,
  }) : this._(
          name: name,
          filter: filter ?? const LedgerFilter(),
          groupBy: groupBy ?? const [],
          template: template ?? Stats.defaults(),
        );

  LedgerView._({
    required this.name,
    required this.filter,
    required this.groupBy,
    required this.template,
  }) : _root = _Node(const GroupKey.none(), template);

  /// Current immutable snapshot of the maintained tree. Safe to hold or
  /// transform; future updates don't mutate it.
  QueryResult get result => _cached ??= _build(_root, 0);

  /// Wipes the maintained state and replays [txs]. Called on registration
  /// and on `ledger.rebuildViews()`.
  void seed(Iterable<Transaction> txs) {
    _root.stats = template;
    _root.children.clear();
    _root.txs.clear();
    for (final tx in txs) {
      applySave(null, tx);
    }
    _cached = null;
  }

  /// Diffs [oldVersion] vs [newVersion] and updates the maintained tree.
  /// [oldVersion] is null for a brand-new transaction. [newVersion]'s
  /// matching legs may be empty (e.g. it's now soft-deleted and the view's
  /// filter excludes deleted) — then only the revert path runs.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    // Revert the old version: re-apply each old leg with `deleted` flipped so
    // the per-stat convention subtracts the prior contribution. Touch only
    // existing nodes — a revert never creates a bucket.
    final oldPaths = <List<GroupKey>>[];
    if (oldVersion != null) {
      for (final leg in filter.apply(oldVersion)) {
        final path = _pathFor(leg, oldVersion);
        oldPaths.add(path);
        _applyAlong(path, leg, _flipDeleted(oldVersion), create: false);
      }
    }

    // Apply the new version, stamping its rows into the leaves it occupies.
    final newPathKeys = <String>{};
    for (final leg in filter.apply(newVersion)) {
      final path = _pathFor(leg, newVersion);
      newPathKeys.add(_pathKey(path));
      _applyAlong(path, leg, newVersion, create: true, row: newVersion);
    }

    // Drop the old row from any leaf the new version no longer occupies.
    if (oldVersion != null) {
      for (final path in oldPaths) {
        if (newPathKeys.contains(_pathKey(path))) continue;
        _leafAt(path)?.txs.remove(oldVersion.id);
      }
    }

    // Prune buckets that no longer hold a row so the tree mirrors the journal.
    _prune(_root, 0);
    _cached = null;
  }

  /// Walks root→leaf along [path], folding [leg]/[tx] into every node's
  /// stats. With `create: true` missing nodes are spun up from [template];
  /// with `create: false` (the revert path) a missing node aborts the walk.
  /// When [row] is non-null it is stamped into the leaf's overlay.
  void _applyAlong(
    List<GroupKey> path,
    Leg leg,
    Transaction tx, {
    required bool create,
    Transaction? row,
  }) {
    var node = _root;
    node.stats = node.stats.apply(leg, tx);
    for (final key in path) {
      var child = node.children[key];
      if (child == null) {
        if (!create) return; // reverting a path that isn't there — no-op
        child = _Node(key, template);
        node.children[key] = child;
      }
      child.stats = child.stats.apply(leg, tx);
      node = child;
    }
    if (row != null) node.txs[row.id] = row;
  }

  _Node? _leafAt(List<GroupKey> path) {
    var node = _root;
    for (final key in path) {
      final child = node.children[key];
      if (child == null) return null;
      node = child;
    }
    return node;
  }

  /// Removes empty subtrees bottom-up. Returns whether [node] is now empty
  /// (and removable by its parent). The root is never removed by the caller.
  bool _prune(_Node node, int depth) {
    if (depth == groupBy.length) return node.txs.isEmpty;
    node.children.removeWhere((_, child) => _prune(child, depth + 1));
    return node.children.isEmpty;
  }

  QueryResult _build(_Node node, int depth) {
    if (depth == groupBy.length) {
      return QueryResult.leaf(
        key: node.key,
        source: TransactionSource.materialized(node.txs.values),
        stats: node.stats,
      );
    }
    return QueryResult.node(
      key: node.key,
      children: [for (final c in node.children.values) _build(c, depth + 1)],
      stats: node.stats,
    );
  }

  List<GroupKey> _pathFor(Leg leg, Transaction tx) =>
      [for (final dim in groupBy) dim.keyFor(leg, tx)];

  Transaction _flipDeleted(Transaction tx) =>
      tx.copyWith(deleted: !tx.deleted);

  String _pathKey(List<GroupKey> path) =>
      path.map((k) => k.toString()).join(' ');
}

/// One node of a [LedgerView]'s maintained tree. Internal nodes route to
/// [children] by the next dimension's [GroupKey]; leaves (at depth
/// `groupBy.length`) hold the row overlay [txs]. Every node carries its own
/// [stats], maintained directly by [LedgerView._applyAlong].
class _Node {
  final GroupKey key;
  Stats stats;
  final Map<GroupKey, _Node> children = {};
  final Map<TransactionId, Transaction> txs = {};

  _Node(this.key, this.stats);
}
