import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/transaction.dart';

/// The base directory for app data files.
final dataDirectoryProvider = FutureProvider<Directory>((ref) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dataDir = Directory('${appDir.path}/expense_tracker');
  if (!await dataDir.exists()) {
    await dataDir.create(recursive: true);
  }
  return dataDir;
});

/// Repository providers — depend on dataDirectory.
final currencyRepositoryProvider = FutureProvider<CurrencyRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return CurrencyRepository(filePath: '${dir.path}/currencies.jsonl');
});

final accountRepositoryProvider = FutureProvider<AccountRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return AccountRepository(filePath: '${dir.path}/accounts.jsonl');
});

final categoryRepositoryProvider = FutureProvider<CategoryRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return CategoryRepository(filePath: '${dir.path}/categories.jsonl');
});

final transactionRepositoryProvider = FutureProvider<TransactionRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return TransactionRepository(filePath: '${dir.path}/transactions.jsonl');
});

/// Data providers — load entities from repositories.
final currenciesProvider = FutureProvider<List<Currency>>((ref) async {
  final repo = await ref.watch(currencyRepositoryProvider.future);
  return repo.getAll();
});

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  return repo.getAll();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repo = await ref.watch(categoryRepositoryProvider.future);
  return repo.getAll();
});

final transactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repo = await ref.watch(transactionRepositoryProvider.future);
  return repo.getAll();
});
