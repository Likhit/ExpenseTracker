import '../data/storage/file_sync.dart';

/// Whether the ledger is accepting writes or waiting for a sync conflict to be
/// resolved.
///
/// After [LedgerService.sync] merges divergent files, entities edited on both
/// sides leave the ledger [LedgerConflicted]; writes are rejected until
/// [LedgerService.resolveConflicts] returns it to [LedgerReady].
sealed class LedgerState {
  const LedgerState();
}

/// Normal operation — writes are accepted.
class LedgerReady extends LedgerState {
  const LedgerReady();
}

/// A merge surfaced [conflicts] (entities edited on both sides). Writes are
/// rejected until they're resolved. The merged tree provisionally reflects the
/// other side's version of each conflicting entity.
class LedgerConflicted extends LedgerState {
  /// Heterogeneous across repositories (account/category/currency/transaction).
  final List<EntityConflict> conflicts;

  const LedgerConflicted(this.conflicts);
}

/// Per-conflict resolution: keep our version or theirs.
enum ConflictChoice { ours, theirs }
