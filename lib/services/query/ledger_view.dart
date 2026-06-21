import 'dart:async';

import '../../models/transaction.dart';
import 'ledger_filter.dart';
import 'ledger_group.dart';
import 'ledger_stats.dart';

/// A named, kept-fresh aggregation over the journal — a (filter, groupBy,
/// stats template) plus the [QueryResult] tree it maintains.
///
/// Register one via `LedgerService.register(...)` and read its current tree
/// via `ledger.viewResult(name).result`. The view owns no traversal logic of
/// its own: it forwards each save to [QueryResult.remove]/[QueryResult.add],
/// the same fold `LedgerService.query` uses to build a result from scratch.
class LedgerView {
  final String name;
  final LedgerFilter filter;
  final List<GroupDimension> groupBy;

  /// Empty-state template fixing which [Stat] kinds every node tracks.
  final Stats template;

  /// The maintained tree, mutated in place by [QueryResult.add]/[remove].
  QueryResult _result;

  /// Fires after every mutation ([applySave], [seed], [restore]) — used by
  /// reactivity layers (e.g. Riverpod providers) to re-read [result], since
  /// the tree is mutated in place and `==` won't catch the change.
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

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
  }) : _result = QueryResult.empty(groupBy, template);

  /// The maintained tree. Live: it is mutated in place on the next save, so a
  /// caller that needs a frozen view should copy what it reads.
  QueryResult get result => _result;

  /// Wipes the maintained state and replays [txs]. Called on registration
  /// when there's no fresh persisted snapshot to restore from.
  void seed(Iterable<Transaction> txs) {
    _result = QueryResult.empty(groupBy, template);
    for (final tx in txs) {
      _result.add(tx, filter, groupBy, template);
    }
    _changesController.add(null);
  }

  /// Adopts a [tree] restored from a persisted snapshot as the maintained
  /// state. Its leaves carry [Checkpoint] markers; subsequent saves stack
  /// fresh rows on top via [applySave].
  void restore(QueryResult tree) {
    _result = tree;
    _changesController.add(null);
  }

  /// Forwards a save to the tree: undo the old version's contribution, then
  /// fold the new one. [oldVersion] is null for a brand-new transaction.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    if (oldVersion != null) _result.remove(oldVersion, filter, groupBy);
    _result.add(newVersion, filter, groupBy, template);
    _changesController.add(null);
  }

  /// Closes the [changes] stream; call when discarding the view.
  Future<void> dispose() => _changesController.close();
}
