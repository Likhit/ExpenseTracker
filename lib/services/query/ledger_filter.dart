import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/path_helper.dart';
import '../../models/transaction.dart';

part 'ledger_filter.freezed.dart';

/// Predicate over the journal. Splits naturally into transaction-level
/// constraints (date, type, deleted) and leg-level constraints (account,
/// currency, category).
///
/// All fields are optional; a missing field means "no constraint on this
/// dimension". An empty filter matches everything (except soft-deleted
/// rows, by default).
@freezed
abstract class LedgerFilter with _$LedgerFilter {
  const LedgerFilter._();

  const factory LedgerFilter({
    Set<AccountId>? accounts,
    Set<CurrencyCode>? currencies,
    Set<CategoryPath>? categories,
    DateTime? from,
    DateTime? to,
    Set<TransactionType>? types,
    @Default(false) bool includeDeleted,
  }) = _LedgerFilter;

  /// Returns the legs of [tx] that satisfy this filter. Empty list if
  /// the transaction itself is filtered out (e.g., wrong date, deleted),
  /// regardless of legs.
  List<Leg> apply(Transaction tx) {
    if (!_matchesTransaction(tx)) return const [];
    return tx.legs.where(_matchesLeg).toList(growable: false);
  }

  bool _matchesTransaction(Transaction tx) {
    if (!includeDeleted && tx.deleted) return false;
    if (from != null && tx.date.isBefore(from!)) return false;
    if (to != null && tx.date.isAfter(to!)) return false;
    if (types != null && !types!.contains(tx.type)) return false;
    return true;
  }

  bool _matchesLeg(Leg leg) {
    if (accounts != null && !accounts!.contains(leg.accountId)) return false;
    if (currencies != null && !currencies!.contains(leg.currencyCode)) {
      return false;
    }
    if (categories != null && !_matchesCategory(leg.categoryPath)) {
      return false;
    }
    return true;
  }

  bool _matchesCategory(CategoryPath? legCategory) {
    if (legCategory == null) return false;
    return categories!.any(legCategory.matches);
  }
}
