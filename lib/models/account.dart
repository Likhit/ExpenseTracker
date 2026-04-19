import 'package:freezed_annotation/freezed_annotation.dart';

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
abstract class Account with _$Account {
  const Account._();

  const factory Account({
    required String id,
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

  /// Returns the segments of the path (e.g., "Chase::Checking" -> ["Chase", "Checking"]).
  List<String> get pathSegments => path.split('::');

  /// Returns the top-level group name (e.g., "Chase::Checking" -> "Chase").
  String get group => pathSegments.first;

  /// Returns the leaf name (e.g., "Chase::Checking" -> "Checking").
  String get displayName => pathSegments.last;
}
