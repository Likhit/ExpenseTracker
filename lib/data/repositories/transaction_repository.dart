import '../../models/ids.dart';
import '../../models/transaction.dart';
import '../storage/jsonl_store.dart';
import 'repository.dart';

class TransactionRepository extends Repository<TransactionId, Transaction> {
  TransactionRepository({required String filePath})
      : super(JsonlStore<TransactionId, Transaction>(
          filePath: filePath,
          fromJson: Transaction.fromJson,
        ));
}
