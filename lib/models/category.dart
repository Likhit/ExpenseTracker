import 'package:freezed_annotation/freezed_annotation.dart';
import '../data/storage/jsonl_storable.dart';
import 'ids.dart';
import 'path_helper.dart';
import 'transaction.dart';

part 'category.freezed.dart';
part 'category.g.dart';

@freezed
abstract class Category
    with _$Category, PathHelper
    implements JsonlStorable<String> {
  const Category._();

  const factory Category({
    required String id,
    @CategoryPathConverter() required CategoryPath path,
    required TransactionType parentType,
    String? icon,
    String? color,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool deleted,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);

  @override
  String get pathString => path.value;

  @override
  Category withDeleted(DateTime updatedAt) =>
      copyWith(deleted: true, updatedAt: updatedAt);
}
