import '../../models/transaction.dart';
import '../storage/jsonl_store.dart';

class TransactionRepository {
  final JsonlStore<Transaction> _store;

  TransactionRepository({required String filePath})
      : _store = JsonlStore<Transaction>(
          filePath: filePath,
          fromJson: Transaction.fromJson,
          toJson: (t) => t.toJson(),
          getId: (t) => t.id,
          getUpdatedAt: (t) => t.updatedAt,
          getCreatedAt: (t) => t.createdAt,
        );

  Future<List<Transaction>> getAll() =>
      _store.readActive((t) => t.deleted);

  Future<void> save(Transaction transaction) => _store.append(transaction);

  Future<void> saveAll(List<Transaction> transactions) =>
      _store.appendAll(transactions);

  Future<void> delete(Transaction transaction) => _store.append(
        transaction.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
