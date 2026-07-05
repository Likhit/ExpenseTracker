import 'package:uuid/uuid.dart';

import '../models/currency.dart';
import '../models/ids.dart';
import 'ledger_service.dart';

/// Seeds the currencies repo with a small curated set of common fiats and
/// cryptos, but only on a truly fresh ledger (zero entries — including
/// soft-deleted, so a user who deliberately cleared the list isn't fought).
///
/// Matches the UX-spec onboarding default list (USD, EUR, GBP, INR, JPY, BTC,
/// ETH). The user can prune or extend the set from the Currencies screen at
/// any time.
Future<void> seedDefaultCurrenciesIfEmpty(LedgerService ledger) async {
  final existing = await ledger.currencies.getAll();
  if (existing.isNotEmpty) return;
  const uuid = Uuid();
  final now = DateTime.now();
  for (final draft in _defaults) {
    await ledger.save(Currency(
      id: CurrencyId(uuid.v4()),
      code: CurrencyCode(draft.code),
      name: draft.name,
      type: draft.type,
      symbol: draft.symbol,
      decimalPlaces: draft.decimalPlaces,
      createdAt: now,
    ));
  }
}

class _Draft {
  final String code;
  final String name;
  final CurrencyType type;
  final String? symbol;
  final int decimalPlaces;
  const _Draft(this.code, this.name, this.type, this.symbol, this.decimalPlaces);
}

const _defaults = <_Draft>[
  _Draft('USD', 'US Dollar', CurrencyType.fiat, r'$', 2),
  _Draft('EUR', 'Euro', CurrencyType.fiat, '€', 2),
  _Draft('GBP', 'British Pound', CurrencyType.fiat, '£', 2),
  _Draft('INR', 'Indian Rupee', CurrencyType.fiat, '₹', 2),
  _Draft('JPY', 'Japanese Yen', CurrencyType.fiat, '¥', 0),
  _Draft('BTC', 'Bitcoin', CurrencyType.crypto, '₿', 8),
  _Draft('ETH', 'Ethereum', CurrencyType.crypto, 'Ξ', 8),
];
