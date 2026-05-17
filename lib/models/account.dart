import 'package:freezed_annotation/freezed_annotation.dart';
import '../data/storage/jsonl_storable.dart';
import 'ids.dart';
import 'line_id.dart';
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
    LineId? lineId,
    @Default(LineId.first()) LineId prev,
  }) = _Account;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  /// Stable id of the built-in Expense account that every ledger owns.
  /// Created automatically by `LedgerService.create`; never deleted.
  static const AccountId expenseId = AccountId('builtin-expense');

  /// Stable id of the built-in Income account. Same lifecycle as
  /// [expenseId].
  static const AccountId incomeId = AccountId('builtin-income');

  @override
  String get pathString => path;

  @override
  Account withDeleted(DateTime updatedAt) =>
      copyWith(deleted: true, updatedAt: updatedAt);

  @override
  Account withChain({required LineId lineId, required LineId prev}) =>
      copyWith(lineId: lineId, prev: prev);
}
