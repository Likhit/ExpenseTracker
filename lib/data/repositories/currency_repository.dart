import '../../models/currency.dart';
import '../storage/jsonl_store.dart';

class CurrencyRepository {
  final JsonlStore<Currency> _store;

  CurrencyRepository({required String filePath})
      : _store = JsonlStore<Currency>(
          filePath: filePath,
          fromJson: Currency.fromJson,
          toJson: (c) => c.toJson(),
          getId: (c) => c.id,
          getUpdatedAt: (c) => c.updatedAt,
          getCreatedAt: (c) => c.createdAt,
        );

  Future<List<Currency>> getAll() =>
      _store.readActive((c) => c.deleted);

  Future<void> save(Currency currency) => _store.append(currency);

  Future<void> saveAll(List<Currency> currencies) =>
      _store.appendAll(currencies);

  Future<void> delete(Currency currency) => _store.append(
        currency.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
