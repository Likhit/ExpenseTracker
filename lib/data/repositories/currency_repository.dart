import '../../models/currency.dart';
import '../../models/ids.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class CurrencyRepository extends Repository<CurrencyId, Currency> {
  CurrencyRepository({required String filePath})
      : super(JsonlStore<CurrencyId, Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
        ));
}
