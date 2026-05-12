import 'package:freezed_annotation/freezed_annotation.dart';
import '../data/storage/jsonl_storable.dart';
import 'ids.dart';
import 'path_helper.dart';

part 'account.freezed.dart';
part 'account.g.dart';

enum AccountType {
  asset,
  liability,
  income,
  expense,
  equity,
}

@freezed
abstract class Account
    with _$Account, PathHelper
    implements JsonlStorable<AccountId> {
  const Account._();

  const factory Account({
    @AccountIdConverter() required AccountId id,
    required String path,
    required AccountType type,
    @Default(false) bool isVirtual,
    String? notes,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool deleted,
  }) = _Account;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  @override
  String get pathString => path;

  @override
  Account withDeleted(DateTime updatedAt) =>
      copyWith(deleted: true, updatedAt: updatedAt);
}
