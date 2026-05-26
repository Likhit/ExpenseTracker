import 'package:decimal/decimal.dart';

import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';

/// Incrementally maintainable aggregate over the journal.
///
/// A [Stat] is an immutable value plus three operations:
/// - [apply] folds one more leg into the running aggregate.
/// - [combine] merges two stats of the same kind (used at node level
///   to roll up children's stats).
/// - [value] exposes the underlying aggregate.
///
/// Apply respects the soft-delete flag on its transaction: a leg from a
/// `tx.deleted == true` contributes the *negative* of the same leg from
/// a non-deleted tx. That single rule covers both:
/// - building a fresh aggregate (every active tx contributes, every
///   deleted tx subtracts back to zero for already-counted versions),
/// - incrementally reverting a previous version when editing or
///   soft-deleting (call `apply` again with the same leg but with the
///   tx's `deleted` flag flipped).
abstract interface class Stat<V> {
  V get value;

  Stat<V> apply(Leg leg, Transaction tx);

  /// Folds [other] of the same kind into this stat. Used to roll up a
  /// node's stats from its children.
  Stat<V> combine(covariant Stat<V> other);

  /// Stable tag identifying this stat kind, used to persist and later
  /// reconstruct it (see [statFromJson]).
  String get kind;

  /// JSON-encodable snapshot of this stat's value, for persistence.
  Object toJson();
}

/// Reconstructs a [Stat] from its persisted [kind] tag and [json] value.
/// The inverse of [Stat.toJson]; new stat kinds register a case here.
Stat statFromJson(String kind, Object? json) {
  switch (kind) {
    case 'count':
      return CountStat(value: json as int);
    case 'sumByCurrency':
      final map = (json as Map).cast<String, Object?>();
      return SumByCurrencyStat(value: {
        for (final entry in map.entries)
          CurrencyCode(entry.key): Decimal.parse(entry.value as String),
      });
    default:
      throw ArgumentError.value(kind, 'kind', 'Unknown stat kind');
  }
}

/// Counts the legs contributing to a bucket. Each non-deleted leg adds
/// 1; each deleted leg subtracts 1.
class CountStat implements Stat<int> {
  @override
  final int value;

  const CountStat({this.value = 0});

  static const empty = CountStat();

  @override
  CountStat apply(Leg leg, Transaction tx) =>
      CountStat(value: value + (tx.deleted ? -1 : 1));

  @override
  CountStat combine(covariant CountStat other) =>
      CountStat(value: value + other.value);

  @override
  String get kind => 'count';

  @override
  Object toJson() => value;

  @override
  bool operator ==(Object other) => other is CountStat && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CountStat($value)';
}

/// Sums each leg's signed amount by its currency. Deleted-tx legs
/// subtract; non-deleted-tx legs add.
class SumByCurrencyStat implements Stat<Map<CurrencyCode, Decimal>> {
  @override
  final Map<CurrencyCode, Decimal> value;

  const SumByCurrencyStat({this.value = const {}});

  static const empty = SumByCurrencyStat();

  @override
  SumByCurrencyStat apply(Leg leg, Transaction tx) {
    final delta = tx.deleted ? -leg.amount : leg.amount;
    final updated = Map<CurrencyCode, Decimal>.from(value);
    updated.update(
      leg.currencyCode,
      (existing) => existing + delta,
      ifAbsent: () => delta,
    );
    return SumByCurrencyStat(value: updated);
  }

  @override
  SumByCurrencyStat combine(covariant SumByCurrencyStat other) {
    final merged = Map<CurrencyCode, Decimal>.from(value);
    other.value.forEach((ccy, amount) {
      merged.update(ccy, (existing) => existing + amount,
          ifAbsent: () => amount);
    });
    return SumByCurrencyStat(value: merged);
  }

  @override
  String get kind => 'sumByCurrency';

  @override
  Object toJson() =>
      {for (final e in value.entries) e.key.value: e.value.toString()};

  @override
  bool operator ==(Object other) =>
      other is SumByCurrencyStat && _mapEquals(value, other.value);

  @override
  int get hashCode => Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'SumByCurrencyStat($value)';
}

bool _mapEquals(Map<CurrencyCode, Decimal> a, Map<CurrencyCode, Decimal> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
