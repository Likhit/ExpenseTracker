import 'package:freezed_annotation/freezed_annotation.dart';

part 'leg.freezed.dart';
part 'leg.g.dart';

@freezed
abstract class Leg with _$Leg {
  const factory Leg({
    required String accountId,
    required String amount,
    required String currencyCode,
    String? categoryPath,
  }) = _Leg;

  factory Leg.fromJson(Map<String, dynamic> json) => _$LegFromJson(json);
}
