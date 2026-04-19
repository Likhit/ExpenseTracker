import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';
part 'category.g.dart';

enum CategoryParentType {
  income,
  expense,
}

@freezed
abstract class Category with _$Category {
  const Category._();

  const factory Category({
    required String id,
    required String path,
    required CategoryParentType parentType,
    String? icon,
    String? color,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool deleted,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);

  /// Returns the segments of the path (e.g., "Food::Snacks::Cake" -> ["Food", "Snacks", "Cake"]).
  List<String> get pathSegments => path.split('::');

  /// Returns the root category name (e.g., "Food::Snacks::Cake" -> "Food").
  String get root => pathSegments.first;

  /// Returns the leaf name (e.g., "Food::Snacks::Cake" -> "Cake").
  String get displayName => pathSegments.last;

  /// Returns the depth of the category (e.g., "Food" -> 1, "Food::Snacks" -> 2).
  int get depth => pathSegments.length;
}
