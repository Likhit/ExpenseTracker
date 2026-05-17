import 'package:expense_tracker/data/storage/jsonl_storable.dart';
import 'package:expense_tracker/models/line_id.dart';

extension type const TestId(String value) {}

/// Hand-rolled [JsonlStorable] used only by the generic Repository tests.
///
/// Lives outside the production models so the Repository contract can be
/// exercised without coupling to any real domain type.
class TestEntity implements JsonlStorable<TestId> {
  @override
  final TestId id;
  final String value;
  @override
  final DateTime createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final bool deleted;
  @override
  final LineId? lineId;
  @override
  final LineId prev;

  const TestEntity({
    required this.id,
    required this.value,
    required this.createdAt,
    this.updatedAt,
    this.deleted = false,
    this.lineId,
    this.prev = const LineId.first(),
  });

  TestEntity copyWith({String? value}) => TestEntity(
        id: id,
        value: value ?? this.value,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deleted: deleted,
        lineId: lineId,
        prev: prev,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id.value,
        'value': value,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'deleted': deleted,
        if (lineId != null) 'lineId': lineId!.toJson(),
        'prev': prev.toJson(),
      };

  factory TestEntity.fromJson(Map<String, dynamic> json) => TestEntity(
        id: TestId(json['id'] as String),
        value: json['value'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        deleted: json['deleted'] as bool? ?? false,
        lineId: json['lineId'] == null
            ? null
            : LineId.fromJson(json['lineId'] as Map<String, dynamic>),
        prev: LineId.fromJson(json['prev'] as Map<String, dynamic>),
      );

  @override
  TestEntity withDeleted(DateTime updatedAt) => TestEntity(
        id: id,
        value: value,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deleted: true,
        lineId: lineId,
        prev: prev,
      );

  @override
  TestEntity withChain({required LineId lineId, required LineId prev}) =>
      TestEntity(
        id: id,
        value: value,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deleted: deleted,
        lineId: lineId,
        prev: prev,
      );
}
