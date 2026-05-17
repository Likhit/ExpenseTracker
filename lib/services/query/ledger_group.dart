import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';

part 'ledger_group.freezed.dart';

/// Time-bucket granularity for [GroupDimension.byTime].
enum TimeBucket { day, week, month, year }

/// One axis to group by. Compose multiple dimensions into a list for
/// nested grouping; `[ByAccount, ByCurrency]` produces a tree keyed by
/// account at the top level, then by currency under each account.
@freezed
sealed class GroupDimension with _$GroupDimension {
  const GroupDimension._();

  const factory GroupDimension.byAccount() = ByAccount;

  /// Groups by category truncated to [depth] segments. A leg with
  /// `Food::Snacks::Cake` at depth 2 groups under `Food::Snacks`. If
  /// the leg's category is shorter than [depth], the whole path is used.
  /// Legs without a category fall under [GroupKey.none].
  const factory GroupDimension.byCategory({@Default(1) int depth}) =
      ByCategory;

  const factory GroupDimension.byCurrency() = ByCurrency;

  const factory GroupDimension.byTime(TimeBucket bucket) = ByTime;

  /// Resolves the group key for [leg] under this dimension. [tx] is
  /// passed for transaction-level fields (currently only [ByTime] uses
  /// it via `tx.date`).
  GroupKey keyFor(Leg leg, Transaction tx) {
    return switch (this) {
      ByAccount() => GroupKey.account(leg.accountId),
      ByCategory(:final depth) => _categoryKey(leg.categoryPath, depth),
      ByCurrency() => GroupKey.currency(leg.currencyCode),
      ByTime(:final bucket) => GroupKey.time(_bucketStart(tx.date, bucket)),
    };
  }

  GroupKey _categoryKey(CategoryPath? path, int depth) {
    if (path == null) return const GroupKey.none();
    final segments = path.value.split('::');
    if (segments.length <= depth) return GroupKey.category(path);
    return GroupKey.category(
      CategoryPath(segments.take(depth).join('::')),
    );
  }

  DateTime _bucketStart(DateTime d, TimeBucket b) {
    switch (b) {
      case TimeBucket.day:
        return DateTime.utc(d.year, d.month, d.day);
      case TimeBucket.week:
        final day = DateTime.utc(d.year, d.month, d.day);
        // ISO weekday: Monday=1..Sunday=7. Anchor weeks to Monday.
        return day.subtract(Duration(days: day.weekday - 1));
      case TimeBucket.month:
        return DateTime.utc(d.year, d.month, 1);
      case TimeBucket.year:
        return DateTime.utc(d.year, 1, 1);
    }
  }
}

/// Key for one group within a [GroupedStats] tree. Each dimension
/// produces its own variant; [GroupKey.none] is the catch-all for legs
/// that lack the grouping field (e.g., legs without a categoryPath when
/// grouping by category) and also marks the root of every result tree.
@freezed
sealed class GroupKey with _$GroupKey {
  const factory GroupKey.account(AccountId id) = AccountKey;
  const factory GroupKey.category(CategoryPath path) = CategoryKey;
  const factory GroupKey.currency(CurrencyCode code) = CurrencyKey;
  const factory GroupKey.time(DateTime bucketStart) = TimeKey;
  const factory GroupKey.none() = NoneKey;
}
