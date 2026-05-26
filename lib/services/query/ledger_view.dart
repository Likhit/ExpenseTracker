import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';

/// A named, kept-fresh aggregation over the journal — a (filter, groupBy,
/// stats template) plus the [QueryResult] it maintains.
///
/// Register one via `LedgerService.register(...)` and read its current tree
/// via `ledger.viewResult(name)!.result`. The service feeds every save into
/// [applySave], which updates the maintained [QueryResult] in place (well,
/// functionally — each update returns a fresh immutable tree), so reads never
/// re-scan the journal.
///
/// Maintenance mirrors how the engine aggregates: a node's stats are the fold
/// of every leg beneath it. A save walks the root→leaf path of each of its
/// legs and `apply`s the leg to every node on the way down — no roll-up pass.
/// An edit/delete first re-applies the *old* version's legs with `deleted`
/// flipped (the [Stat] convention turns that into a subtract), then applies
/// the new version's, and finally drops emptied buckets so the tree mirrors
/// the journal.
class LedgerView {
  final String name;
  final LedgerFilter filter;
  final List<GroupDimension> groupBy;

  /// Empty-state template fixing which [Stat] kinds every node tracks.
  final Stats template;

  /// The maintained tree. Each [applySave] replaces it with an updated copy.
  QueryResult _result;

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
  }) : _result = _empty(groupBy, template);

  /// Current immutable snapshot of the maintained tree. Safe to hold or
  /// transform; future updates produce new trees rather than mutating it.
  QueryResult get result => _result;

  /// Wipes the maintained state and replays [txs]. Called on registration.
  void seed(Iterable<Transaction> txs) {
    _result = _empty(groupBy, template);
    for (final tx in txs) {
      applySave(null, tx);
    }
  }

  /// Diffs [oldVersion] vs [newVersion] and updates the maintained tree.
  /// [oldVersion] is null for a brand-new transaction. [newVersion]'s
  /// matching legs may be empty (e.g. it's now soft-deleted and the view's
  /// filter excludes deleted) — then only the revert path runs.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    // Revert the old version: re-apply each old leg with `deleted` flipped so
    // the per-stat convention subtracts the prior contribution.
    final oldPaths = <List<GroupKey>>[];
    if (oldVersion != null) {
      for (final leg in filter.apply(oldVersion)) {
        final path = _pathFor(leg, oldVersion);
        oldPaths.add(path);
        _result = _fold(_result, path, 0, leg, _flipDeleted(oldVersion), null);
      }
    }

    // Apply the new version, stamping its rows into the leaves it occupies.
    final newPathKeys = <String>{};
    for (final leg in filter.apply(newVersion)) {
      final path = _pathFor(leg, newVersion);
      newPathKeys.add(_pathKey(path));
      _result = _fold(_result, path, 0, leg, newVersion, newVersion);
    }

    // Drop the old row from any leaf the new version no longer occupies.
    if (oldVersion != null) {
      for (final path in oldPaths) {
        if (newPathKeys.contains(_pathKey(path))) continue;
        _result = _dropRow(_result, path, 0, oldVersion.id);
      }
    }

    // Prune buckets that no longer hold a row so the tree mirrors the journal.
    _result = _prune(_result, 0) ?? _empty(groupBy, template);
  }

  /// Folds [leg]/[tx] into every node's stats along [path] from [depth],
  /// returning the rebuilt subtree. Missing nodes are created (from
  /// [template]) only when [row] is non-null — i.e. on the apply pass; on the
  /// revert pass the path always pre-exists. When [row] is non-null it is
  /// stamped into the destination leaf.
  QueryResult _fold(
    QueryResult node,
    List<GroupKey> path,
    int depth,
    Leg leg,
    Transaction tx,
    Transaction? row,
  ) {
    final stats = node.stats.apply(leg, tx);
    if (depth == path.length) {
      final leaf = node as LeafResult;
      return QueryResult.leaf(
        key: leaf.key,
        source: row == null ? leaf.source : _stamp(leaf.source, row),
        stats: stats,
      );
    }
    final n = node as NodeResult;
    final key = path[depth];
    final children = n.children.toList();
    final i = children.indexWhere((c) => c.key == key);
    if (i >= 0) {
      children[i] = _fold(children[i], path, depth + 1, leg, tx, row);
    } else if (row != null) {
      children.add(
          _fold(_emptyNode(key, depth + 1), path, depth + 1, leg, tx, row));
    }
    return QueryResult.node(key: n.key, children: children, stats: stats);
  }

  /// Removes [id] from the leaf at [path] (used when an edit moves a row out
  /// of a bucket). Leaves stats untouched — the revert pass already handled
  /// them.
  QueryResult _dropRow(
    QueryResult node,
    List<GroupKey> path,
    int depth,
    TransactionId id,
  ) {
    if (depth == path.length) {
      final leaf = node as LeafResult;
      return QueryResult.leaf(
        key: leaf.key,
        source: _unstamp(leaf.source, id),
        stats: leaf.stats,
      );
    }
    final n = node as NodeResult;
    final children = n.children.toList();
    final i = children.indexWhere((c) => c.key == path[depth]);
    if (i < 0) return node;
    children[i] = _dropRow(children[i], path, depth + 1, id);
    return QueryResult.node(key: n.key, children: children, stats: n.stats);
  }

  /// Drops empty subtrees bottom-up. Returns the pruned node, or null when it
  /// is now empty and its parent should drop it. The root (depth 0) is kept
  /// even when empty.
  QueryResult? _prune(QueryResult node, int depth) {
    if (depth == groupBy.length) {
      return (node as LeafResult).source.materialized.isEmpty ? null : node;
    }
    final n = node as NodeResult;
    final kept = <QueryResult>[];
    for (final child in n.children) {
      final pruned = _prune(child, depth + 1);
      if (pruned != null) kept.add(pruned);
    }
    if (depth > 0 && kept.isEmpty) return null;
    return QueryResult.node(key: n.key, children: kept, stats: n.stats);
  }

  QueryResult _emptyNode(GroupKey key, int depth) => depth == groupBy.length
      ? QueryResult.leaf(key: key, source: const TransactionSource(), stats: template)
      : QueryResult.node(key: key, children: const [], stats: template);

  List<GroupKey> _pathFor(Leg leg, Transaction tx) =>
      [for (final dim in groupBy) dim.keyFor(leg, tx)];

  Transaction _flipDeleted(Transaction tx) =>
      tx.copyWith(deleted: !tx.deleted);

  String _pathKey(List<GroupKey> path) =>
      path.map((k) => k.toString()).join(' ');
}

QueryResult _empty(List<GroupDimension> groupBy, Stats template) =>
    groupBy.isEmpty
        ? QueryResult.leaf(
            key: const GroupKey.none(),
            source: const TransactionSource(),
            stats: template,
          )
        : QueryResult.node(
            key: const GroupKey.none(),
            children: const [],
            stats: template,
          );

TransactionSource _stamp(TransactionSource source, Transaction row) =>
    TransactionSource(materialized: [
      for (final t in source.materialized)
        if (t.id != row.id) t,
      row,
    ]);

TransactionSource _unstamp(TransactionSource source, TransactionId id) =>
    TransactionSource(materialized: [
      for (final t in source.materialized)
        if (t.id != id) t,
    ]);
