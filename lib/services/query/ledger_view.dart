import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';

/// A named, kept-fresh aggregation over the journal — a (filter, groupBy,
/// stats template) plus the [QueryResult] tree it maintains.
///
/// Register one via `LedgerService.register(...)` and read its current tree
/// via `ledger.viewResult(name)!.result`. The service feeds every save into
/// [applySave], which mutates the tree in place, so reads never re-scan the
/// journal.
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

  /// The maintained tree, mutated in place by [applySave].
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
  }) : _result = _emptyRoot(groupBy, template);

  /// The maintained tree. Live: it is mutated in place on the next save, so a
  /// caller that needs a frozen view should copy what it reads.
  QueryResult get result => _result;

  /// Wipes the maintained state and replays [txs]. Called on registration.
  void seed(Iterable<Transaction> txs) {
    _result = _emptyRoot(groupBy, template);
    for (final tx in txs) {
      applySave(null, tx);
    }
  }

  /// Diffs [oldVersion] vs [newVersion] and updates the tree in place.
  /// [oldVersion] is null for a brand-new transaction. [newVersion]'s matching
  /// legs may be empty (e.g. it's now soft-deleted and the view's filter
  /// excludes deleted) — then only the revert path runs.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    // Revert the old version: re-apply each old leg with `deleted` flipped so
    // the per-stat convention subtracts the prior contribution.
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
        _dropRow(path, oldVersion.id);
      }
    }

    // Prune buckets that no longer hold a row so the tree mirrors the journal.
    _prune(_result, 0);
  }

  /// Walks root→leaf along [path], folding [leg]/[tx] into every node's stats.
  /// With `create: true` missing nodes are spun up from [template] (the apply
  /// pass); with `create: false` (the revert pass) the path always pre-exists.
  /// When [row] is non-null it is stamped into the destination leaf.
  void _applyAlong(
    List<GroupKey> path,
    Leg leg,
    Transaction tx, {
    required bool create,
    Transaction? row,
  }) {
    QueryResult node = _result;
    node.stats = node.stats.apply(leg, tx);
    for (var depth = 0; depth < path.length; depth++) {
      final parent = node as NodeResult;
      final key = path[depth];
      var child = _childFor(parent, key);
      if (child == null) {
        if (!create) return; // reverting a path that isn't there — no-op
        child = _emptyNode(key, depth + 1);
        parent.children.add(child);
      }
      child.stats = child.stats.apply(leg, tx);
      node = child;
    }
    if (row != null) {
      final leaf = node as LeafResult;
      leaf.source = _stamp(leaf.source, row);
    }
  }

  /// Removes [id] from the leaf at [path] (used when an edit moves a row out
  /// of a bucket). Stats are untouched — the revert pass already handled them.
  void _dropRow(List<GroupKey> path, TransactionId id) {
    final leaf = _leafAt(path);
    if (leaf is LeafResult) leaf.source = _unstamp(leaf.source, id);
  }

  /// Drops empty subtrees bottom-up. Returns whether [node] is now empty and
  /// its parent should remove it. The root (depth 0) is kept even when empty.
  bool _prune(QueryResult node, int depth) {
    if (depth == groupBy.length) {
      return (node as LeafResult).source.materialized.isEmpty && depth > 0;
    }
    final n = node as NodeResult;
    n.children.removeWhere((child) => _prune(child, depth + 1));
    return n.children.isEmpty && depth > 0;
  }

  QueryResult? _leafAt(List<GroupKey> path) {
    QueryResult node = _result;
    for (final key in path) {
      if (node is! NodeResult) return null;
      final child = _childFor(node, key);
      if (child == null) return null;
      node = child;
    }
    return node;
  }

  QueryResult? _childFor(NodeResult node, GroupKey key) {
    for (final child in node.children) {
      if (child.key == key) return child;
    }
    return null;
  }

  QueryResult _emptyNode(GroupKey key, int depth) => depth == groupBy.length
      ? LeafResult(key: key, source: const TransactionSource(), stats: template)
      : NodeResult(key: key, children: [], stats: template);

  List<GroupKey> _pathFor(Leg leg, Transaction tx) =>
      [for (final dim in groupBy) dim.keyFor(leg, tx)];

  Transaction _flipDeleted(Transaction tx) =>
      tx.copyWith(deleted: !tx.deleted);

  String _pathKey(List<GroupKey> path) =>
      path.map((k) => k.toString()).join(' ');
}

QueryResult _emptyRoot(List<GroupDimension> groupBy, Stats template) =>
    groupBy.isEmpty
        ? LeafResult(
            key: const GroupKey.none(),
            source: const TransactionSource(),
            stats: template,
          )
        : NodeResult(
            key: const GroupKey.none(),
            children: [],
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
