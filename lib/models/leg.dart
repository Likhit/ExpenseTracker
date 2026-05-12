import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'leg.freezed.dart';
part 'leg.g.dart';

@freezed
abstract class Leg with _$Leg {
  const factory Leg({
    @AccountIdConverter() required AccountId accountId,
    @DecimalConverter() required Decimal amount,
    @CurrencyCodeConverter() required CurrencyCode currencyCode,
    @NullableCategoryPathConverter() CategoryPath? categoryPath,
  }) = _Leg;

  factory Leg.fromJson(Map<String, dynamic> json) => _$LegFromJson(json);
}

class DecimalConverter implements JsonConverter<Decimal, String> {
  const DecimalConverter();
  @override
  Decimal fromJson(String json) => Decimal.parse(json);
  @override
  String toJson(Decimal object) => object.toString();
}
