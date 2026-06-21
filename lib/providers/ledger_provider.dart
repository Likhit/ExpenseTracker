import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/transaction.dart';
import '../services/ledger_service.dart';
import '../services/ledger_state.dart';

part 'ledger_provider.g.dart';

/// The single [LedgerService] for the app. Async because `create()` opens
/// JSONL files and runs the startup sync; `keepAlive` because it's the root
/// service that the UI keeps watching for its entire lifetime.
@Riverpod(keepAlive: true)
Future<LedgerService> ledger(Ref ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final service = await LedgerService.create(
    accountsPath: '${dir.path}/accounts.jsonl',
    categoriesPath: '${dir.path}/categories.jsonl',
    currenciesPath: '${dir.path}/currencies.jsonl',
    transactionsPath: '${dir.path}/transactions.jsonl',
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Latest [LedgerState], refreshed on every change the engine emits — so the
/// UI can switch to the conflict screen the moment a sync surfaces conflicts.
@riverpod
Stream<LedgerState> ledgerState(Ref ref) async* {
  final service = await ref.watch(ledgerProvider.future);
  yield service.state;
  await for (final _ in service.changes) {
    yield service.state;
  }
}

/// Latest active accounts. Emits an initial value and re-emits whenever the
/// engine's [LedgerService.changes] fires (a write completed).
@riverpod
Stream<List<Account>> accounts(Ref ref) =>
    _liveRead(ref, (s) => s.accounts.getAll());

@riverpod
Stream<List<Category>> categories(Ref ref) =>
    _liveRead(ref, (s) => s.categories.getAll());

@riverpod
Stream<List<Currency>> currencies(Ref ref) =>
    _liveRead(ref, (s) => s.currencies.getAll());

@riverpod
Stream<List<Transaction>> transactions(Ref ref) =>
    _liveRead(ref, (s) => s.transactions.getAll());

/// Shared "yield once, then yield again on every change" helper for the
/// read-side providers. Keeps each provider above to one line.
Stream<T> _liveRead<T>(
  Ref ref,
  Future<T> Function(LedgerService) read,
) async* {
  final service = await ref.watch(ledgerProvider.future);
  yield await read(service);
  await for (final _ in service.changes) {
    yield await read(service);
  }
}
