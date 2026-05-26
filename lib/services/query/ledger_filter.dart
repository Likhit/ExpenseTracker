import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/path_helper.dart';
import '../../models/transaction.dart';

part 'ledger_filter.freezed.dart';
part 'ledger_filter.g.dart';

/// Predicate over the journal. Splits naturally into transaction-level
/// constraints (date, type, deleted) and leg-level constraints (account,
/// currency, category — each with optional include/exclude sets).
///
/// All fields are optional. A missing include field means "no positive
/// constraint on this dimension"; a missing exclude field means "nothing
/// is excluded on this dimension". When both are present, a leg must
/// satisfy the include AND not appear in the exclude. An empty filter
/// matches everything (except soft-deleted rows, by default).
@freezed
abstract class LedgerFilter with _$LedgerFilter {
  const LedgerFilter._();

  const factory LedgerFilter({
    @AccountIdConverter() Set<AccountId>? accounts,
    @CurrencyCodeConverter() Set<CurrencyCode>? currencies,
    @CategoryPathConverter() Set<CategoryPath>? categories,
    @AccountIdConverter() Set<AccountId>? excludeAccounts,
    @CurrencyCodeConverter() Set<CurrencyCode>? excludeCurrencies,
    @CategoryPathConverter() Set<CategoryPath>? excludeCategories,
    DateTime? from,
    DateTime? to,
    Set<TransactionType>? types,
    @Default(false) bool includeDeleted,
  }) = _LedgerFilter;

  factory LedgerFilter.fromJson(Map<String, dynamic> json) =>
      _$LedgerFilterFromJson(json);

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
    if (categories != null && !_matchesAnyCategory(leg.categoryPath, categories!)) {
      return false;
    }
    if (excludeAccounts != null && excludeAccounts!.contains(leg.accountId)) {
      return false;
    }
    if (excludeCurrencies != null &&
        excludeCurrencies!.contains(leg.currencyCode)) {
      return false;
    }
    if (excludeCategories != null &&
        _matchesAnyCategory(leg.categoryPath, excludeCategories!)) {
      return false;
    }
    return true;
  }

  /// Segment-aware membership: leg's [categoryPath] matches any path in
  /// [set]. A null leg category never matches.
  bool _matchesAnyCategory(CategoryPath? legCategory, Set<CategoryPath> set) {
    if (legCategory == null) return false;
    return set.any(legCategory.matches);
  }
}
