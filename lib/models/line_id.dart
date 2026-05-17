import 'package:freezed_annotation/freezed_annotation.dart';

part 'line_id.freezed.dart';
part 'line_id.g.dart';

/// Identifier for a single appended line in a JSONL repository file.
///
/// Algebraic: either [First] (sentinel for "no previous append exists in
/// this file") or [Of] (the UUID of a real, persisted append). Modeled
/// as a sealed type so the start-of-chain case is not represented by
/// `null` — null is reserved for "entity has never been saved at all".
@Freezed(unionKey: 'kind')
sealed class LineId with _$LineId {
  const LineId._();

  /// Sentinel marking the start of a chain. Used as `prev` for the very
  /// first append into a repository file.
  const factory LineId.first() = First;

  /// A real lineId backed by a UUID. Always the form taken by an
  /// entity's own `lineId` after it has been persisted, and by `prev`
  /// for every append after the first.
  const factory LineId.of(String value) = Of;

  factory LineId.fromJson(Map<String, dynamic> json) => _$LineIdFromJson(json);
}
