import '../../models/line_id.dart';
import 'jsonl_storable.dart';

/// An entity that was edited on *both* sides of a sync fork — i.e. the same
/// id was appended in both divergent chains after their common ancestor.
///
/// [ours] / [theirs] are the latest post-fork version on each side. The merge
/// linearizes both into the chain regardless (no history is lost); a conflict
/// is surfaced so a caller can decide which version should win as the entity's
/// current state.
class EntityConflict<Id, T extends JsonlStorable<Id>> {
  final Id id;
  final T ours;
  final T theirs;

  const EntityConflict({
    required this.id,
    required this.ours,
    required this.theirs,
  });
}

/// Outcome of [mergeChains]: the single linearized [merged] chain plus any
/// [conflicts] (entities edited on both sides).
typedef ChainMergeResult<Id, T extends JsonlStorable<Id>> = ({
  List<T> merged,
  List<EntityConflict<Id, T>> conflicts,
});

/// Merges two divergent append-chains of the *same* repository file into one
/// linear chain — a rebase.
///
/// Both chains are in append order and share a common prefix: the run of
/// leading appends with identical `lineId`s (the state both sides last synced).
/// After the fork point each side has its own appends. The result keeps the
/// shared prefix and [ours] suffix as-is, then replays [theirs]' suffix on top
/// by rewriting each append's `prev` to chain onto the running tip — keeping
/// their original `lineId`s (UUIDs, so no collision), which makes re-running
/// the merge idempotent.
///
/// State is reconstructed as latest-version-per-id, so every append survives;
/// for an entity edited on both sides, *theirs* lands last and would provisionally
/// win — but such entities are also returned in `conflicts` so the caller can
/// override the winner. Merging more than two copies is done pairwise.
ChainMergeResult<Id, T> mergeChains<Id, T extends JsonlStorable<Id>>(
  List<T> ours,
  List<T> theirs,
) {
  var fork = 0;
  while (fork < ours.length &&
      fork < theirs.length &&
      ours[fork].lineId == theirs[fork].lineId) {
    fork++;
  }
  final ourSuffix = ours.sublist(fork);
  final theirSuffix = theirs.sublist(fork);

  final ourIds = {for (final e in ourSuffix) e.id};
  final conflicts = <EntityConflict<Id, T>>[];
  final reported = <Id>{};
  for (final theirEntity in theirSuffix) {
    if (ourIds.contains(theirEntity.id) && reported.add(theirEntity.id)) {
      conflicts.add(EntityConflict(
        id: theirEntity.id,
        ours: ourSuffix.lastWhere((e) => e.id == theirEntity.id),
        theirs: theirSuffix.lastWhere((e) => e.id == theirEntity.id),
      ));
    }
  }

  final merged = <T>[...ours];
  var prev = merged.isEmpty ? const LineId.first() : merged.last.lineId!;
  for (final theirEntity in theirSuffix) {
    merged.add(theirEntity.withChain(lineId: theirEntity.lineId!, prev: prev) as T);
    prev = theirEntity.lineId!;
  }

  return (merged: merged, conflicts: conflicts);
}
