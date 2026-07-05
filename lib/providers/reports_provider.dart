import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/query/ledger_filter.dart';
import '../services/query/ledger_group.dart';
import '../services/query/ledger_stats.dart';
import 'ledger_provider.dart';

part 'reports_provider.freezed.dart';
part 'reports_provider.g.dart';

/// A report's identity: the `(filter, groupBy)` pair passed to `ledger.query`.
/// Freezed gives it value equality (deep-comparing the `groupBy` list), so it
/// works as a Riverpod family key — two screens asking for the same spec share
/// one provider instance.
@freezed
abstract class ReportSpec with _$ReportSpec {
  const factory ReportSpec({
    @Default(LedgerFilter()) LedgerFilter filter,
    @Default(<GroupDimension>[]) List<GroupDimension> groupBy,
  }) = _ReportSpec;
}

/// The [QueryResult] for [spec], recomputed on every engine change so report
/// screens stay live. Backed by `ledger.query` (a full fold each time) rather
/// than a registered `LedgerView`: correct and simple at personal-ledger
/// scale. A card that re-renders hot enough to care can be migrated to a
/// maintained view once `LedgerService` grows a `deregister` for provider
/// lifecycle; until then the recompute keeps the wiring trivial.
@riverpod
Stream<QueryResult> report(Ref ref, ReportSpec spec) async* {
  final ledger = await ref.watch(ledgerProvider.future);
  yield await ledger.query(spec.filter, groupBy: spec.groupBy);
  await for (final _ in ledger.changes) {
    yield await ledger.query(spec.filter, groupBy: spec.groupBy);
  }
}
