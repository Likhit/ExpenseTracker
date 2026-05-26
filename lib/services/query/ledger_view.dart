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

  /// Wipes the maintained state and replays [txs]. Called on registration.
  void seed(Iterable<Transaction> txs) {
    _result = QueryResult.empty(groupBy, template);
    for (final tx in txs) {
      _result.add(tx, filter, groupBy, template);
    }
  }

  /// Forwards a save to the tree: undo the old version's contribution, then
  /// fold the new one. [oldVersion] is null for a brand-new transaction.
  void applySave(Transaction? oldVersion, Transaction newVersion) {
    if (oldVersion != null) _result.remove(oldVersion, filter, groupBy);
    _result.add(newVersion, filter, groupBy, template);
  }
}
