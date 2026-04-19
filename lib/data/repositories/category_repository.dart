import '../../models/category.dart';
import '../storage/jsonl_store.dart';

class CategoryRepository {
  final JsonlStore<Category> _store;

  CategoryRepository({required String filePath})
      : _store = JsonlStore<Category>(
          filePath: filePath,
          fromJson: Category.fromJson,
          toJson: (c) => c.toJson(),
          getId: (c) => c.id,
          getUpdatedAt: (c) => c.updatedAt,
          getCreatedAt: (c) => c.createdAt,
        );

  Future<List<Category>> getAll() =>
      _store.readActive((c) => c.deleted);

  Future<void> save(Category category) => _store.append(category);

  Future<void> saveAll(List<Category> categories) =>
      _store.appendAll(categories);

  Future<void> delete(Category category) => _store.append(
        category.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
