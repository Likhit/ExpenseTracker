import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';
import '../widgets/account_picker.dart';
import '../widgets/category_picker.dart';
import '../widgets/category_visuals.dart';
import '../widgets/currency_input.dart';
import '../widgets/date_chips.dart';

const _uuid = Uuid();

/// Single-leg-asset entry screen for an Expense or Income transaction.
///
/// **Expense**: the asset/liability account is the *source*, the built-in
/// `Expense` account is the bare balancing sink. The asset-side leg carries
/// the category (see `Transaction.validate` rule).
///
/// **Income**: the asset/liability account is the *destination*, the built-in
/// `Income` account is the bare balancing source. The asset-side leg carries
/// the category.
///
/// Editing an existing transaction is supported by passing [existing] —
/// fields are prefilled and Save reuses the existing id (which the engine's
/// append-chain treats as a new version).
class ExpenseIncomeEntryScreen extends ConsumerStatefulWidget {
  final TransactionType type;
  final Transaction? existing;

  const ExpenseIncomeEntryScreen({
    required this.type,
    this.existing,
    super.key,
  });

  @override
  ConsumerState<ExpenseIncomeEntryScreen> createState() =>
      _ExpenseIncomeEntryScreenState();
}

class _ExpenseIncomeEntryScreenState
    extends ConsumerState<ExpenseIncomeEntryScreen> {
  Decimal? _amount;
  CurrencyCode? _currency;
  Category? _category;
  Account? _account;
  late TextEditingController _description;
  late DateTime _date;
  String? _saveError;
  bool _saving = false;
  // Set once the account/category objects behind an edit's asset leg have been
  // resolved from the (async) providers. Guards the one-shot prefill in build.
  bool _prefilled = false;

  bool get _isExpense => widget.type == TransactionType.expense;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.date ?? DateTime.now();
    _description = TextEditingController(text: existing?.description ?? '');
    // For edits, pull the prefill from the asset-side leg (the one not on the
    // built-in sink/source). The account/category *objects* need the providers
    // loaded, so they're resolved lazily in build (see `_prefillFromExisting`).
    if (existing != null) {
      final assetLeg = existing.legs.firstWhere((l) =>
          l.accountId != Account.expenseId && l.accountId != Account.incomeId);
      _amount = assetLeg.amount.abs();
      _currency = assetLeg.currencyCode;
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAccount() async {
    // `.future` ensures the provider is initialized and the first value has
    // arrived — `ref.read(...).value` returns null until then.
    final accounts = await ref.read(accountsProvider.future);
    if (!mounted) return;
    final picked = await pickAccount(context,
        accounts: accounts,
        title: _isExpense ? 'Source account' : 'Destination account');
    if (picked != null) setState(() => _account = picked);
  }

  Future<void> _pickCategory() async {
    // Eagerly seed the categories provider before opening the picker — the
    // picker itself watches it, but a clean ledger needs at least one tick
    // for `await for` to enter.
    await ref.read(categoriesProvider.future);
    if (!mounted) return;
    final picked = await pickCategory(context, parentType: widget.type);
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saveError = null;
      _saving = true;
    });
    final amount = _amount;
    final currency = _currency;
    final category = _category;
    final account = _account;
    if (amount == null || amount == Decimal.zero) {
      setState(() {
        _saveError = 'Enter an amount';
        _saving = false;
      });
      return;
    }
    if (currency == null) {
      setState(() {
        _saveError = 'Pick a currency';
        _saving = false;
      });
      return;
    }
    if (category == null) {
      setState(() {
        _saveError = 'Pick a category';
        _saving = false;
      });
      return;
    }
    if (account == null) {
      setState(() {
        _saveError = _isExpense
            ? 'Pick a source account'
            : 'Pick a destination account';
        _saving = false;
      });
      return;
    }

    final ledger = await ref.read(ledgerProvider.future);
    final now = DateTime.now();
    final existing = widget.existing;

    // Expense: asset leg negative (money out), Expense sink positive.
    // Income:  asset leg positive (money in),  Income source negative.
    final signedAsset = _isExpense ? -amount : amount;
    final signedSink = _isExpense ? amount : -amount;
    final sinkAccount =
        _isExpense ? Account.expenseId : Account.incomeId;

    final tx = Transaction(
      id: existing?.id ?? TransactionId(_uuid.v4()),
      date: _date,
      description: _description.text.trim(),
      type: widget.type,
      legs: [
        Leg(
          accountId: account.id,
          amount: signedAsset,
          currencyCode: currency,
          categoryPath: category.path,
        ),
        Leg(
          accountId: sinkAccount,
          amount: signedSink,
          currencyCode: currency,
        ),
      ],
      createdAt: existing?.createdAt ?? now,
      updatedAt: existing == null ? null : now,
    );

    final result = await ledger.save(tx);
    if (!mounted) return;
    if (!result.isValid) {
      setState(() {
        _saveError = result.errorMessage;
        _saving = false;
      });
      return;
    }
    Navigator.of(context).pop(tx);
  }

  /// Resolve an edit's account/category *objects* from the loaded providers and
  /// fill the pickers. Runs once, when both providers have a value.
  void _prefillFromExisting(
      List<Account> accounts, List<Category> categories) {
    final existing = widget.existing;
    if (existing == null || _prefilled) return;
    _prefilled = true;
    final assetLeg = existing.legs.firstWhere((l) =>
        l.accountId != Account.expenseId && l.accountId != Account.incomeId);
    _account = accounts
        .where((a) => a.id == assetLeg.accountId)
        .cast<Account?>()
        .firstWhere((_) => true, orElse: () => null);
    final path = assetLeg.categoryPath;
    if (path != null) {
      _category = categories
              .where((c) => c.path.value == path.value && !c.deleted)
              .cast<Category?>()
              .firstWhere((_) => true, orElse: () => null) ??
          // The category was deleted since; keep a display-only stand-in so the
          // tile shows the original path and Save preserves it.
          Category(
            id: CategoryId(_uuid.v4()),
            path: path,
            parentType: widget.type,
            createdAt: existing.createdAt,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const [];
    // Prime the accounts/categories providers up front so the pickers (which
    // read them) see fully-loaded data the first time they're opened.
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    // Default currency: first active fiat, else first of any.
    if (_currency == null && currencies.isNotEmpty) {
      final active = currencies.where((c) => !c.deleted).toList();
      if (active.isNotEmpty) _currency = active.first.code;
    }
    // One-shot prefill of the account/category tiles for edits, once both the
    // accounts and categories providers have resolved.
    if (accountsAsync.hasValue && categoriesAsync.hasValue) {
      _prefillFromExisting(accountsAsync.value!, categoriesAsync.value!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? (_isExpense ? 'Edit expense' : 'Edit income')
            : (_isExpense ? 'New expense' : 'New income')),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CurrencyInputField(
              label: 'Amount',
              currencies: currencies.where((c) => !c.deleted).toList(),
              selectedCurrency: _currency,
              initialAmount: _amount,
              onAmountChanged: (v) => _amount = v,
              onCurrencyChanged: (code) => setState(() => _currency = code),
            ),
            const SizedBox(height: 24),
            _PickerTile(
              icon: Icons.label_outline,
              label: 'Category',
              value: _category?.path.value,
              leadingFor: _category == null
                  ? null
                  : _categoryLeading(theme, _category!),
              onTap: _pickCategory,
            ),
            const SizedBox(height: 12),
            _PickerTile(
              icon: Icons.account_balance_wallet_outlined,
              label: _isExpense ? 'Source account' : 'Destination account',
              value: _account?.path,
              onTap: _pickAccount,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 24),
            DateChips(
              value: _date,
              onChanged: (d) => setState(() => _date = d),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Text(_saveError!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryLeading(ThemeData theme, Category category) {
    final all = ref.read(categoriesProvider).value ?? const [];
    final rootName = category.pathSegments.first;
    final root = all
        .where((c) => !c.deleted && c.path.value == rootName)
        .cast<Category?>()
        .firstWhere((_) => true, orElse: () => null);
    final tint = parseCategoryColor(root?.color) ?? theme.colorScheme.secondary;
    return CircleAvatar(
      backgroundColor: tint.withValues(alpha: 0.2),
      foregroundColor: tint,
      child: Icon(categoryIconFor(root?.icon)),
    );
  }
}

/// Picker-row tile: shows label + selected value, or a hint when empty. Pulls
/// double duty as both the category and the account picker target.
class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? leadingFor;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.leadingFor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            leadingFor ?? Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  Text(
                    value ?? 'Tap to pick',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: value == null
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
