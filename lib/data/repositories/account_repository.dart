import '../../models/account.dart';
import '../../models/ids.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class AccountRepository extends Repository<AccountId, Account> {
  AccountRepository({required String filePath})
      : super(JsonlStore<AccountId, Account>(
          filePath: filePath,
          fromJson: Account.fromJson,
        ));
}
