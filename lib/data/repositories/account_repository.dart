import '../../models/account.dart';
import '../storage/jsonl_store.dart';

class AccountRepository {
  final JsonlStore<Account> _store;

  AccountRepository({required String filePath})
      : _store = JsonlStore<Account>(
          filePath: filePath,
          fromJson: Account.fromJson,
          toJson: (a) => a.toJson(),
          getId: (a) => a.id,
          getUpdatedAt: (a) => a.updatedAt,
          getCreatedAt: (a) => a.createdAt,
        );

  Future<List<Account>> getAll() =>
      _store.readActive((a) => a.deleted);

  Future<void> save(Account account) => _store.append(account);

  Future<void> saveAll(List<Account> accounts) =>
      _store.appendAll(accounts);

  Future<void> delete(Account account) => _store.append(
        account.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
