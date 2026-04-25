import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/transaction.dart';

const _uuid = Uuid();

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
final currencyRepositoryProvider =
    FutureProvider<CurrencyRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return CurrencyRepository(filePath: '${dir.path}/currencies.jsonl');
});

final accountRepositoryProvider =
    FutureProvider<AccountRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return AccountRepository(filePath: '${dir.path}/accounts.jsonl');
});

final categoryRepositoryProvider =
    FutureProvider<CategoryRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return CategoryRepository(filePath: '${dir.path}/categories.jsonl');
});

final transactionRepositoryProvider =
    FutureProvider<TransactionRepository>((ref) async {
  final dir = await ref.watch(dataDirectoryProvider.future);
  return TransactionRepository(filePath: '${dir.path}/transactions.jsonl');
});

// ---------------------------------------------------------------------------
// Currency notifier
// ---------------------------------------------------------------------------

final currenciesProvider =
    AsyncNotifierProvider<CurrenciesNotifier, List<Currency>>(
        CurrenciesNotifier.new);

class CurrenciesNotifier extends AsyncNotifier<List<Currency>> {
  @override
  Future<List<Currency>> build() async {
    final repo = await ref.watch(currencyRepositoryProvider.future);
    final currencies = await repo.getAll();
    if (currencies.isEmpty) {
      await _seedDefaults(repo);
      return repo.getAll();
    }
    return currencies;
  }

  Future<void> _seedDefaults(CurrencyRepository repo) async {
    final now = DateTime.now();
    await repo.saveAll(defaultCurrencies(now));
  }

  Future<void> add(Currency currency) async {
    final repo = await ref.read(currencyRepositoryProvider.future);
    await repo.save(currency);
    ref.invalidateSelf();
  }

  Future<void> edit(Currency currency) async {
    final repo = await ref.read(currencyRepositoryProvider.future);
    await repo.save(currency.copyWith(updatedAt: DateTime.now()));
    ref.invalidateSelf();
  }

  Future<void> remove(Currency currency) async {
    final repo = await ref.read(currencyRepositoryProvider.future);
    await repo.delete(currency);
    ref.invalidateSelf();
  }
}

List<Currency> defaultCurrencies(DateTime now) => [
      Currency(
          id: _uuid.v4(),
          code: 'USD',
          name: 'US Dollar',
          type: CurrencyType.fiat,
          symbol: r'$',
          createdAt: now),
      Currency(
          id: _uuid.v4(),
          code: 'EUR',
          name: 'Euro',
          type: CurrencyType.fiat,
          symbol: '€',
          createdAt: now),
      Currency(
          id: _uuid.v4(),
          code: 'GBP',
          name: 'British Pound',
          type: CurrencyType.fiat,
          symbol: '£',
          createdAt: now),
      Currency(
          id: _uuid.v4(),
          code: 'JPY',
          name: 'Japanese Yen',
          type: CurrencyType.fiat,
          symbol: '¥',
          decimalPlaces: 0,
          createdAt: now),
      Currency(
          id: _uuid.v4(),
          code: 'INR',
          name: 'Indian Rupee',
          type: CurrencyType.fiat,
          symbol: '₹',
          createdAt: now),
    ];

// ---------------------------------------------------------------------------
// Account notifier
// ---------------------------------------------------------------------------

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<Account>>(
        AccountsNotifier.new);

class AccountsNotifier extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() async {
    final repo = await ref.watch(accountRepositoryProvider.future);
    return repo.getAll();
  }

  Future<void> add(Account account) async {
    final repo = await ref.read(accountRepositoryProvider.future);
    await repo.save(account);
    ref.invalidateSelf();
  }

  Future<void> edit(Account account) async {
    final repo = await ref.read(accountRepositoryProvider.future);
    await repo.save(account.copyWith(updatedAt: DateTime.now()));
    ref.invalidateSelf();
  }

  Future<void> remove(Account account) async {
    final repo = await ref.read(accountRepositoryProvider.future);
    await repo.delete(account);
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// Category notifier
// ---------------------------------------------------------------------------

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
        CategoriesNotifier.new);

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() async {
    final repo = await ref.watch(categoryRepositoryProvider.future);
    final categories = await repo.getAll();
    if (categories.isEmpty) {
      await _seedDefaults(repo);
      return repo.getAll();
    }
    return categories;
  }

  Future<void> _seedDefaults(CategoryRepository repo) async {
    final now = DateTime.now();
    await repo.saveAll(defaultCategories(now));
  }

  Future<void> add(Category category) async {
    final repo = await ref.read(categoryRepositoryProvider.future);
    await repo.save(category);
    ref.invalidateSelf();
  }

  Future<void> edit(Category category) async {
    final repo = await ref.read(categoryRepositoryProvider.future);
    await repo.save(category.copyWith(updatedAt: DateTime.now()));
    ref.invalidateSelf();
  }

  Future<void> remove(Category category) async {
    final repo = await ref.read(categoryRepositoryProvider.future);
    await repo.delete(category);
    ref.invalidateSelf();
  }

  /// Finds or creates a category by path, returning the category.
  Future<Category> findOrCreate(
      String path, TransactionType parentType) async {
    final current = state.value ?? [];
    final existing = current.where((c) => c.path == path).firstOrNull;
    if (existing != null) return existing;

    final category = Category(
      id: _uuid.v4(),
      path: path,
      parentType: parentType,
      createdAt: DateTime.now(),
    );
    await add(category);
    return category;
  }
}

List<Category> defaultCategories(DateTime now) => [
      // Expense categories
      Category(
          id: _uuid.v4(),
          path: 'Food',
          parentType: TransactionType.expense,
          icon: 'restaurant',
          color: '#FF5722',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Transport',
          parentType: TransactionType.expense,
          icon: 'directions_car',
          color: '#2196F3',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Housing',
          parentType: TransactionType.expense,
          icon: 'home',
          color: '#4CAF50',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Health Care',
          parentType: TransactionType.expense,
          icon: 'local_hospital',
          color: '#E91E63',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Education',
          parentType: TransactionType.expense,
          icon: 'school',
          color: '#9C27B0',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Entertainment',
          parentType: TransactionType.expense,
          icon: 'movie',
          color: '#FF9800',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Shopping',
          parentType: TransactionType.expense,
          icon: 'shopping_bag',
          color: '#795548',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Utilities',
          parentType: TransactionType.expense,
          icon: 'bolt',
          color: '#607D8B',
          createdAt: now),
      // Income categories
      Category(
          id: _uuid.v4(),
          path: 'Salary',
          parentType: TransactionType.income,
          icon: 'work',
          color: '#4CAF50',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Bonus',
          parentType: TransactionType.income,
          icon: 'card_giftcard',
          color: '#FF9800',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Stock Grant',
          parentType: TransactionType.income,
          icon: 'trending_up',
          color: '#2196F3',
          createdAt: now),
      Category(
          id: _uuid.v4(),
          path: 'Interest',
          parentType: TransactionType.income,
          icon: 'account_balance',
          color: '#009688',
          createdAt: now),
    ];

// ---------------------------------------------------------------------------
// Transaction notifier
// ---------------------------------------------------------------------------

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
        TransactionsNotifier.new);

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  @override
  Future<List<Transaction>> build() async {
    final repo = await ref.watch(transactionRepositoryProvider.future);
    return repo.getAll();
  }

  Future<void> add(Transaction transaction) async {
    final repo = await ref.read(transactionRepositoryProvider.future);
    await repo.save(transaction);
    ref.invalidateSelf();
  }

  Future<void> edit(Transaction transaction) async {
    final repo = await ref.read(transactionRepositoryProvider.future);
    await repo.save(transaction.copyWith(updatedAt: DateTime.now()));
    ref.invalidateSelf();
  }

  Future<void> remove(Transaction transaction) async {
    final repo = await ref.read(transactionRepositoryProvider.future);
    await repo.delete(transaction);
    ref.invalidateSelf();
  }
}
