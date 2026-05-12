import '../../models/currency.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class CurrencyRepository extends Repository<String, Currency> {
  CurrencyRepository({required String filePath})
      : super(JsonlStore<String, Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
        ));
}
