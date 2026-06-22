import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/ids.dart';

/// Formats [amount] using [currency]'s `decimalPlaces` and `symbol`. Falls back
/// to a `<code> <number>` form when no [currency] is known (e.g. a leg
/// referencing a currency that has since been deleted).
String formatMoney(Decimal amount, Currency? currency) {
  final decimals = currency?.decimalPlaces ?? 2;
  final symbol = currency?.symbol;
  final code = currency?.code.value;
  final fmt = NumberFormat.decimalPatternDigits(decimalDigits: decimals);
  final magnitude = fmt.format(amount.toDouble());
  if (symbol != null && symbol.isNotEmpty) {
    final sign = amount < Decimal.zero ? '-' : '';
    return '$sign$symbol${magnitude.replaceFirst('-', '')}';
  }
  return code != null ? '$code $magnitude' : magnitude;
}

/// Formats [amount] alongside the bare currency [code], for cases where the
/// caller doesn't have the full [Currency] entity in hand (e.g. a leg whose
/// currency record was deleted). Two decimal places by convention.
String formatMoneyByCode(Decimal amount, CurrencyCode code) {
  final fmt = NumberFormat.decimalPatternDigits(decimalDigits: 2);
  return '${code.value} ${fmt.format(amount.toDouble())}';
}
