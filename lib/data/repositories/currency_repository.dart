import '../../models/currency.dart';
import '../storage/jsonl_store.dart';

class CurrencyRepository {
  final JsonlStore<Currency> _store;

  CurrencyRepository({required String filePath})
      : _store = JsonlStore<Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
        );

  Future<List<Currency>> getAll() => _store.readActive();

  Future<void> save(Currency currency) => _store.append(currency);

  Future<void> saveAll(List<Currency> currencies) =>
      _store.appendAll(currencies);

  Future<void> delete(Currency currency) => _store.append(
        currency.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
