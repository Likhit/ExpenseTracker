import 'package:decimal/decimal.dart';
import '../models/transaction.dart';
import '../models/leg.dart';

/// Computes account balances and validates double-entry invariants.
class LedgerService {
  /// Computes balances per account per currency from a list of transactions.
  ///
  /// Returns a map of accountId -> (currencyCode -> balance).
  /// Positive balance = net debit, negative = net credit.
  Map<String, Map<String, Decimal>> computeBalances(
      List<Transaction> transactions) {
    final balances = <String, Map<String, Decimal>>{};

    for (final tx in transactions) {
      for (final leg in tx.legs) {
        final amount = Decimal.parse(leg.amount);
        balances
            .putIfAbsent(leg.accountId, () => {})
            .update(
              leg.currencyCode,
              (existing) => existing + amount,
              ifAbsent: () => amount,
            );
      }
    }

    return balances;
  }

  /// Computes the balance for a single account across all currencies.
  Map<String, Decimal> accountBalance(
      String accountId, List<Transaction> transactions) {
    final all = computeBalances(transactions);
    return all[accountId] ?? {};
  }

  /// Validates that a transaction's legs balance correctly.
  ///
  /// For same-currency transactions: sum of all legs must be zero.
  /// For cross-currency: each currency's legs are allowed to not sum to zero
  /// (the exchange is recorded in metadata), but there must be exactly
  /// two currencies involved and metadata must contain exchangeRate.
  ValidationResult validate(Transaction transaction) {
    if (transaction.legs.length < 2) {
      return ValidationResult.error('Transaction must have at least 2 legs');
    }

    // Group amounts by currency
    final byCurrency = <String, Decimal>{};
    for (final leg in transaction.legs) {
      final amount = Decimal.tryParse(leg.amount);
      if (amount == null) {
        return ValidationResult.error(
            'Invalid amount "${leg.amount}" in leg');
      }
      byCurrency.update(
        leg.currencyCode,
        (existing) => existing + amount,
        ifAbsent: () => amount,
      );
    }

    if (byCurrency.length == 1) {
      // Same-currency: must sum to zero
      final sum = byCurrency.values.first;
      if (sum != Decimal.zero) {
        return ValidationResult.error(
            'Legs do not balance: sum is $sum (expected 0)');
      }
      return ValidationResult.ok();
    }

    // Cross-currency: must have exactly 2 currencies
    if (byCurrency.length > 2) {
      return ValidationResult.error(
          'Cross-currency transactions must involve exactly 2 currencies, '
          'found ${byCurrency.length}');
    }

    // Cross-currency: metadata must contain exchangeRate
    if (transaction.metadata == null ||
        transaction.metadata!['exchangeRate'] == null) {
      return ValidationResult.error(
          'Cross-currency transactions must include exchangeRate metadata');
    }

    return ValidationResult.ok();
  }

  /// Validates a list of legs before creating a transaction (pre-save check).
  /// Same logic as validate() but works on raw legs + metadata.
  ValidationResult validateLegs(
      List<Leg> legs, Map<String, dynamic>? metadata) {
    if (legs.length < 2) {
      return ValidationResult.error('Transaction must have at least 2 legs');
    }

    final byCurrency = <String, Decimal>{};
    for (final leg in legs) {
      final amount = Decimal.tryParse(leg.amount);
      if (amount == null) {
        return ValidationResult.error(
            'Invalid amount "${leg.amount}" in leg');
      }
      byCurrency.update(
        leg.currencyCode,
        (existing) => existing + amount,
        ifAbsent: () => amount,
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
          'Cross-currency transactions must involve exactly 2 currencies');
    }

    if (metadata == null || metadata['exchangeRate'] == null) {
      return ValidationResult.error(
          'Cross-currency transactions must include exchangeRate metadata');
    }

    return ValidationResult.ok();
  }
}

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._(this.isValid, this.errorMessage);

  factory ValidationResult.ok() => const ValidationResult._(true, null);
  factory ValidationResult.error(String message) =>
      ValidationResult._(false, message);
}
