import '../../models/transaction.dart';
import 'ledger_group.dart';

/// A query leaf's transactions, modelled as a (possibly unhydrated)
/// [Checkpoint] base plus a materialized overlay of rows applied on top.
///
/// Three states arise over a view's lifecycle:
/// - **Fresh in-memory** (a one-shot `LedgerService.query`, or any view while
///   the app is running): [checkpoint] is null and every contributing row
///   sits in [recent].
/// - **Restored from disk, untouched** (Phase 1.8 PR C): [checkpoint]
///   describes the rows folded in at or before the view's watermark; those
///   rows are *not* loaded. [recent] is empty.
/// - **Restored, then live-updated**: [checkpoint] stays as-is — it still
///   stands for the rows up to the watermark — and new saves accumulate in
///   [recent] on top, with no forced hydration.
///
/// The synchronously-available rows are [recent]. Resolving the *full* set
/// (fetching the checkpoint's rows and merging the overlay, overlay winning
/// per id) requires hitting the journal and lands in PR C.
class TransactionSource {
  /// Unhydrated base, or null when the leaf is fully materialized.
  final Checkpoint? checkpoint;

  /// Rows available without touching storage: everything for an in-memory
  /// leaf, or the post-checkpoint overlay for a restored one.
  final List<Transaction> recent;

  const TransactionSource({this.checkpoint, this.recent = const []});

  /// A fully-materialized source — no checkpoint, all rows in hand.
  factory TransactionSource.materialized(Iterable<Transaction> txs) =>
      TransactionSource(recent: List.unmodifiable(txs));

  /// Whether some contributing rows live behind an unhydrated [checkpoint].
  bool get hasCheckpoint => checkpoint != null;

  /// Rows available without hitting storage. When [hasCheckpoint] is true
  /// this is the overlay only — the checkpoint's rows are not included.
  Iterable<Transaction> get recentRows => recent;
}

/// Stand-in for the rows a leaf folded in at or before a view's watermark,
/// kept unhydrated until a drill-down asks for them. Carries the root→leaf
/// group-key [path] needed to rebuild a targeted filter when resolving.
///
/// Resolution is implemented in Phase 1.8 PR C; until then a [Checkpoint]
/// only ever appears in a view restored from disk.
class Checkpoint {
  /// Root→leaf [GroupKey]s identifying the leaf this checkpoint stands for.
  final List<GroupKey> path;

  const Checkpoint(this.path);
}
