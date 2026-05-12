import 'package:json_annotation/json_annotation.dart';

extension type const AccountId(String value) {}

extension type const TransactionId(String value) {}

extension type const CategoryPath(String value) {}

extension type const CurrencyCode(String value) {}

class AccountIdConverter implements JsonConverter<AccountId, String> {
  const AccountIdConverter();
  @override
  AccountId fromJson(String json) => AccountId(json);
  @override
  String toJson(AccountId object) => object.value;
}

class TransactionIdConverter implements JsonConverter<TransactionId, String> {
  const TransactionIdConverter();
  @override
  TransactionId fromJson(String json) => TransactionId(json);
  @override
  String toJson(TransactionId object) => object.value;
}

class CategoryPathConverter implements JsonConverter<CategoryPath, String> {
  const CategoryPathConverter();
  @override
  CategoryPath fromJson(String json) => CategoryPath(json);
  @override
  String toJson(CategoryPath object) => object.value;
}

class NullableCategoryPathConverter
    implements JsonConverter<CategoryPath?, String?> {
  const NullableCategoryPathConverter();
  @override
  CategoryPath? fromJson(String? json) =>
      json == null ? null : CategoryPath(json);
  @override
  String? toJson(CategoryPath? object) => object?.value;
}

class CurrencyCodeConverter implements JsonConverter<CurrencyCode, String> {
  const CurrencyCodeConverter();
  @override
  CurrencyCode fromJson(String json) => CurrencyCode(json);
  @override
  String toJson(CurrencyCode object) => object.value;
}
