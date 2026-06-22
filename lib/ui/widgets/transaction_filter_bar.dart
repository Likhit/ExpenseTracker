import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/ids.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';

/// Filter state for the transactions list. All fields are optional — a missing
/// field means "no constraint on that dimension". The screen passes this to
/// `LedgerFilter` at query time.
class TransactionsFilter {
  final Set<TransactionType>? types;
  final Set<AccountId>? accounts;
  final Set<CategoryPath>? categories;
  final DateTimeRange? dateRange;

  const TransactionsFilter({
    this.types,
    this.accounts,
    this.categories,
    this.dateRange,
  });

  bool get isEmpty =>
      types == null && accounts == null && categories == null && dateRange == null;

  TransactionsFilter copyWith({
    Set<TransactionType>? types,
    Set<AccountId>? accounts,
    Set<CategoryPath>? categories,
    DateTimeRange? dateRange,
    bool clearTypes = false,
    bool clearAccounts = false,
    bool clearCategories = false,
    bool clearDateRange = false,
  }) =>
      TransactionsFilter(
        types: clearTypes ? null : (types ?? this.types),
        accounts: clearAccounts ? null : (accounts ?? this.accounts),
        categories: clearCategories ? null : (categories ?? this.categories),
        dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      );
}

/// Filter chip bar across the top of the transactions list. Each chip opens a
/// focused multi-select sheet (or date range picker for the date chip), and
/// emits the updated [TransactionsFilter] via [onChanged].
class TransactionsFilterBar extends ConsumerWidget {
  final TransactionsFilter filter;
  final ValueChanged<TransactionsFilter> onChanged;

  const TransactionsFilterBar({
    required this.filter,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Chip(
            label: _typeChipLabel(filter.types),
            selected: filter.types != null,
            onTap: () => _pickTypes(context),
            onClear:
                filter.types == null ? null : () => _emitClear(_Field.types),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: _accountChipLabel(filter.accounts,
                ref.watch(accountsProvider).value ?? const []),
            selected: filter.accounts != null,
            onTap: () => _pickAccounts(context, ref),
            onClear: filter.accounts == null
                ? null
                : () => _emitClear(_Field.accounts),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: _categoryChipLabel(filter.categories,
                ref.watch(categoriesProvider).value ?? const []),
            selected: filter.categories != null,
            onTap: () => _pickCategories(context, ref),
            onClear: filter.categories == null
                ? null
                : () => _emitClear(_Field.categories),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: _dateChipLabel(filter.dateRange),
            selected: filter.dateRange != null,
            onTap: () => _pickDateRange(context),
            onClear: filter.dateRange == null
                ? null
                : () => _emitClear(_Field.dateRange),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTypes(BuildContext context) async {
    final selected = filter.types ?? const <TransactionType>{};
    final result = await showModalBottomSheet<Set<TransactionType>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet<TransactionType>(
        title: 'Transaction types',
        initial: selected,
        options: [
          for (final t in TransactionType.values)
            _Option(value: t, label: _typeLabel(t)),
        ],
      ),
    );
    if (result == null) return;
    onChanged(filter.copyWith(
      types: result.isEmpty ? null : result,
      clearTypes: result.isEmpty,
    ));
  }

  Future<void> _pickAccounts(BuildContext context, WidgetRef ref) async {
    final accounts = (await ref.read(accountsProvider.future))
        .where((a) => !a.deleted)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (!context.mounted) return;
    final selected = filter.accounts ?? const <AccountId>{};
    final result = await showModalBottomSheet<Set<AccountId>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet<AccountId>(
        title: 'Accounts',
        initial: selected,
        options: [
          for (final a in accounts) _Option(value: a.id, label: a.path),
        ],
      ),
    );
    if (result == null) return;
    onChanged(filter.copyWith(
      accounts: result.isEmpty ? null : result,
      clearAccounts: result.isEmpty,
    ));
  }

  Future<void> _pickCategories(BuildContext context, WidgetRef ref) async {
    final cats = (await ref.read(categoriesProvider.future))
        .where((c) => !c.deleted)
        .toList()
      ..sort((a, b) => a.path.value.compareTo(b.path.value));
    if (!context.mounted) return;
    final selected = filter.categories ?? const <CategoryPath>{};
    final result = await showModalBottomSheet<Set<CategoryPath>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet<CategoryPath>(
        title: 'Categories',
        initial: selected,
        options: [
          for (final c in cats) _Option(value: c.path, label: c.path.value),
        ],
      ),
    );
    if (result == null) return;
    onChanged(filter.copyWith(
      categories: result.isEmpty ? null : result,
      clearCategories: result.isEmpty,
    ));
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: filter.dateRange,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    onChanged(filter.copyWith(dateRange: picked));
  }

  void _emitClear(_Field field) {
    onChanged(filter.copyWith(
      clearTypes: field == _Field.types,
      clearAccounts: field == _Field.accounts,
      clearCategories: field == _Field.categories,
      clearDateRange: field == _Field.dateRange,
    ));
  }
}

enum _Field { types, accounts, categories, dateRange }

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onPressed: onTap,
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 18),
    );
  }
}

class _Option<T> {
  final T value;
  final String label;
  const _Option({required this.value, required this.label});
}

class _MultiSelectSheet<T> extends StatefulWidget {
  final String title;
  final Set<T> initial;
  final List<_Option<T>> options;

  const _MultiSelectSheet({
    required this.title,
    required this.initial,
    required this.options,
  });

  @override
  State<_MultiSelectSheet<T>> createState() => _MultiSelectSheetState<T>();
}

class _MultiSelectSheetState<T> extends State<_MultiSelectSheet<T>> {
  late Set<T> _picked;

  @override
  void initState() {
    super.initState();
    _picked = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child:
                Text(widget.title, style: theme.textTheme.titleLarge),
          ),
          if (widget.options.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  'Nothing to filter on yet.', style: theme.textTheme.bodyMedium),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in widget.options)
                    CheckboxListTile(
                      value: _picked.contains(opt.value),
                      title: Text(opt.label),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(opt.value);
                        } else {
                          _picked.remove(opt.value);
                        }
                      }),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<T>{}),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_picked),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _typeChipLabel(Set<TransactionType>? types) {
  if (types == null) return 'Type';
  if (types.length == 1) return _typeLabel(types.single);
  return '${types.length} types';
}

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      TransactionType.transfer => 'Transfer',
    };

String _accountChipLabel(Set<AccountId>? accounts, List<Account> all) {
  if (accounts == null) return 'Account';
  if (accounts.length == 1) {
    final id = accounts.single;
    return all
        .where((a) => a.id == id)
        .map((a) => a.path)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => 'Account') ??
        'Account';
  }
  return '${accounts.length} accounts';
}

String _categoryChipLabel(
    Set<CategoryPath>? categories, List<Category> all) {
  if (categories == null) return 'Category';
  if (categories.length == 1) return categories.single.value;
  return '${categories.length} categories';
}

String _dateChipLabel(DateTimeRange? range) {
  if (range == null) return 'Date';
  final fmt = DateFormat.MMMd();
  return '${fmt.format(range.start)} – ${fmt.format(range.end)}';
}
