import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/storage/jsonl_storable.dart';
import 'ids.dart';
import 'leg.dart';
import 'validation_result.dart';

part 'transaction.freezed.dart';
part 'transaction.g.dart';

enum TransactionType {
  expense,
  income,
  transfer,
}

@freezed
abstract class Transaction
    with _$Transaction
    implements JsonlStorable<TransactionId> {
  const Transaction._();

  const factory Transaction({
    @TransactionIdConverter() required TransactionId id,
    required DateTime date,
    required String description,
    required TransactionType type,
    required List<Leg> legs,
    Map<String, dynamic>? metadata,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool deleted,
  }) = _Transaction;

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);

  @override
  Transaction withDeleted(DateTime updatedAt) =>
      copyWith(deleted: true, updatedAt: updatedAt);

  /// Validates that this transaction's legs balance correctly.
  ///
  /// For same-currency transactions: sum of all legs must be zero.
  /// For cross-currency: must involve exactly two currencies and carry
  /// `exchangeRate` in metadata (each currency's legs are not expected
  /// to sum to zero; the exchange is recorded separately).
  ValidationResult validate() {
    if (legs.length < 2) {
      return ValidationResult.error('Transaction must have at least 2 legs');
    }

    final byCurrency = <CurrencyCode, Decimal>{};
    for (final leg in legs) {
      byCurrency.update(
        leg.currencyCode,
        (existing) => existing + leg.amount,
        ifAbsent: () => leg.amount,
      );
    }

    if (byCurrency.length == 1) {
      final sum = byCurrency.values.first;
      if (sum != Decimal.zero) {
        return ValidationResult.error(
            'Legs do not balance: sum is $sum (expected 0)');
      }
      return ValidationResult.ok();
    }

    if (byCurrency.length > 2) {
      return ValidationResult.error(
          'Cross-currency transactions must involve exactly 2 currencies, '
          'found ${byCurrency.length}');
    }

    if (metadata == null || metadata!['exchangeRate'] == null) {
      return ValidationResult.error(
          'Cross-currency transactions must include exchangeRate metadata');
    }

    return ValidationResult.ok();
  }
}
