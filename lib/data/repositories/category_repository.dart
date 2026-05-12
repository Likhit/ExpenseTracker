import '../../models/category.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class CategoryRepository extends Repository<String, Category> {
  CategoryRepository({required String filePath})
      : super(JsonlStore<String, Category>(
          filePath: filePath,
          fromJson: Category.fromJson,
        ));
}
