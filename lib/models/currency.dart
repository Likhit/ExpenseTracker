import 'package:freezed_annotation/freezed_annotation.dart';
import '../data/storage/jsonl_storable.dart';

part 'currency.freezed.dart';
part 'currency.g.dart';

enum CurrencyType {
  fiat,
  stock,
  crypto,
}

@freezed
abstract class Currency with _$Currency implements JsonlStorable {
  const factory Currency({
    required String id,
    required String code,
    required String name,
    required CurrencyType type,
    String? symbol,
    @Default(2) int decimalPlaces,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool deleted,
  }) = _Currency;

  factory Currency.fromJson(Map<String, dynamic> json) =>
      _$CurrencyFromJson(json);
}
