import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/currency.dart';
import '../models/ids.dart';
import 'ledger_provider.dart';

part 'balances_provider.g.dart';

/// Per-account, per-currency balances. Recomputes whenever the engine emits a
/// change. Built on top of `LedgerService.computeBalances()` rather than a
/// maintained `LedgerView`; if balance lookups ever become a bottleneck, swap
/// this for a registered view without touching consumers.
@riverpod
Stream<Map<AccountId, Map<CurrencyCode, Decimal>>> balances(Ref ref) async* {
  final service = await ref.watch(ledgerProvider.future);
  yield await service.computeBalances();
  await for (final _ in service.changes) {
    yield await service.computeBalances();
  }
}

/// Currencies indexed by code, for fast leg → currency lookups in money
/// formatting. Includes soft-deleted entries so an old leg whose currency was
/// later removed still renders with the right `decimalPlaces`.
@riverpod
Map<CurrencyCode, Currency> currenciesByCode(Ref ref) {
  final list = ref.watch(currenciesProvider).value ?? const [];
  return {for (final c in list) c.code: c};
}
