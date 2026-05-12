import '../../models/category.dart';
import '../../models/ids.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class CategoryRepository extends Repository<CategoryId, Category> {
  CategoryRepository({required String filePath})
      : super(JsonlStore<CategoryId, Category>(
          filePath: filePath,
          fromJson: Category.fromJson,
        ));
}
