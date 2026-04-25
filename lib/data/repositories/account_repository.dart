import '../../models/account.dart';
import '../storage/jsonl_store.dart';

class AccountRepository {
  final JsonlStore<Account> _store;

  AccountRepository({required String filePath})
      : _store = JsonlStore<Account>(
          filePath: filePath,
          fromJson: Account.fromJson,
        );

  Future<List<Account>> getAll() => _store.readActive();

  Future<void> save(Account account) => _store.append(account);

  Future<void> saveAll(List<Account> accounts) =>
      _store.appendAll(accounts);

  /// Soft-deletes by appending a new version with deleted=true.
  /// The original line stays in the file (append-only), but readActive()
  /// deduplicates by id and filters deleted entries.
  Future<void> delete(Account account) => _store.append(
        account.copyWith(deleted: true, updatedAt: DateTime.now()),
      );
}
