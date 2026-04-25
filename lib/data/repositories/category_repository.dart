import '../../models/category.dart';
import '../storage/jsonl_store.dart';

class CategoryRepository {
  final JsonlStore<Category> _store;

  CategoryRepository({required String filePath})
      : _store = JsonlStore<Category>(
          filePath: filePath,
          fromJson: Category.fromJson,
        );

  Future<List<Category>> getAll() => _store.readActive();

  Future<void> save(Category category) => _store.append(category);

  Future<void> saveAll(List<Category> categories) =>
      _store.appendAll(categories);

  Future<void> delete(Category category) => _store.append(
        category.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
