import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/account.dart';
import '../../models/ids.dart';
import '../../models/leg.dart';
import '../../models/transaction.dart';
import '../../providers/ledger_provider.dart';
import '../widgets/account_picker.dart';
import '../widgets/currency_input.dart';
import '../widgets/date_chips.dart';

const _uuid = Uuid();

/// Entry screen for a Transfer: money between two user-owned accounts. Both
/// legs are asset/liability accounts; neither carries a category.
///
/// Same-currency transfers ask for a single amount and balance both sides to
/// it. Cross-currency transfers ask for both legs' amounts independently and
/// record `metadata.exchangeRate` so the engine accepts the unbalanced sum.
class TransferEntryScreen extends ConsumerStatefulWidget {
  final Transaction? existing;

  const TransferEntryScreen({this.existing, super.key});

  @override
  ConsumerState<TransferEntryScreen> createState() =>
      _TransferEntryScreenState();
}

class _TransferEntryScreenState extends ConsumerState<TransferEntryScreen> {
  Account? _from;
  Account? _to;
  Decimal? _amountFrom;
  Decimal? _amountTo;
  CurrencyCode? _currencyFrom;
  CurrencyCode? _currencyTo;
  late TextEditingController _description;
  late DateTime _date;
  String? _saveError;
  bool _saving = false;
  // Guards the one-shot resolution of the from/to account objects for an edit.
  bool _prefilled = false;

  bool get _crossCurrency =>
      _currencyFrom != null &&
      _currencyTo != null &&
      _currencyFrom != _currencyTo;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.date ?? DateTime.now();
    _description = TextEditingController(text: existing?.description ?? '');
    if (existing != null && existing.legs.length == 2) {
      // The "from" leg has the negative amount; "to" has the positive.
      final from =
          existing.legs.firstWhere((l) => l.amount < Decimal.zero);
      final to = existing.legs.firstWhere((l) => l.amount > Decimal.zero);
      _amountFrom = from.amount.abs();
      _amountTo = to.amount;
      _currencyFrom = from.currencyCode;
      _currencyTo = to.currencyCode;
      // The account *objects* are resolved lazily in build once the accounts
      // provider has loaded (see `_prefillAccounts`).
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final accounts = await ref.read(accountsProvider.future);
    if (!mounted) return;
    final picked = await pickAccount(context,
        accounts: accounts,
        exclude: _to,
        title: 'From account');
    if (picked == null) return;
    setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final accounts = await ref.read(accountsProvider.future);
    if (!mounted) return;
    final picked = await pickAccount(context,
        accounts: accounts,
        exclude: _from,
        title: 'To account');
    if (picked == null) return;
    setState(() => _to = picked);
  }

  /// Resolve the from/to account objects for an edit once the accounts provider
  /// has loaded. Runs once.
  void _prefillAccounts(List<Account> accounts) {
    final existing = widget.existing;
    if (existing == null || _prefilled || existing.legs.length != 2) return;
    _prefilled = true;
    Account? lookup(AccountId id) => accounts
        .where((a) => a.id == id)
        .cast<Account?>()
        .firstWhere((_) => true, orElse: () => null);
    final fromLeg = existing.legs.firstWhere((l) => l.amount < Decimal.zero);
    final toLeg = existing.legs.firstWhere((l) => l.amount > Decimal.zero);
    _from = lookup(fromLeg.accountId);
    _to = lookup(toLeg.accountId);
  }

  Future<void> _save() async {
    setState(() {
      _saveError = null;
      _saving = true;
    });

    final from = _from;
    final to = _to;
    final currencyFrom = _currencyFrom;
    final currencyTo = _currencyTo;
    final amountFrom = _amountFrom;
    if (from == null || to == null) {
      _fail('Pick both accounts');
      return;
    }
    if (from.id == to.id) {
      _fail('Source and destination must differ');
      return;
    }
    if (currencyFrom == null) {
      _fail('Pick a currency');
      return;
    }
    if (amountFrom == null || amountFrom == Decimal.zero) {
      _fail('Enter an amount');
      return;
    }

    Decimal amountTo;
    Map<String, dynamic>? metadata;
    if (_crossCurrency) {
      final to2 = _amountTo;
      if (to2 == null || to2 == Decimal.zero) {
        _fail('Enter the destination amount');
        return;
      }
      amountTo = to2;
      final rate = (amountTo / amountFrom).toDecimal(scaleOnInfinitePrecision: 20);
      metadata = {
        'exchangeRate': {
          'from': currencyFrom.value,
          'to': currencyTo!.value,
          'rate': rate.toString(),
        }
      };
    } else {
      amountTo = amountFrom;
    }

    final ledger = await ref.read(ledgerProvider.future);
    final now = DateTime.now();
    final existing = widget.existing;
    final tx = Transaction(
      id: existing?.id ?? TransactionId(_uuid.v4()),
      date: _date,
      description: _description.text.trim(),
      type: TransactionType.transfer,
      legs: [
        Leg(
            accountId: from.id,
            amount: -amountFrom,
            currencyCode: currencyFrom),
        Leg(
            accountId: to.id,
            amount: amountTo,
            currencyCode: _crossCurrency ? currencyTo! : currencyFrom),
      ],
      metadata: metadata,
      createdAt: existing?.createdAt ?? now,
      updatedAt: existing == null ? null : now,
    );

    final result = await ledger.save(tx);
    if (!mounted) return;
    if (!result.isValid) {
      _fail(result.errorMessage ?? 'Save failed');
      return;
    }
    Navigator.of(context).pop(tx);
  }

  void _fail(String msg) =>
      setState(() {
        _saveError = msg;
        _saving = false;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const [];
    // Prime accounts up front so the From/To pickers (which read it lazily)
    // see fully-loaded data on first open.
    final accountsAsync = ref.watch(accountsProvider);
    if (accountsAsync.hasValue) _prefillAccounts(accountsAsync.value!);
    final active = currencies.where((c) => !c.deleted).toList();
    if (_currencyFrom == null && active.isNotEmpty) {
      _currencyFrom = active.first.code;
    }
    // Default the destination currency to match source until the user changes it.
    _currencyTo ??= _currencyFrom;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'Edit transfer' : 'New transfer'),
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
            _AccountTile(
              label: 'From',
              icon: Icons.north_east,
              account: _from,
              onTap: _pickFrom,
            ),
            const SizedBox(height: 12),
            _AccountTile(
              label: 'To',
              icon: Icons.south_west,
              account: _to,
              onTap: _pickTo,
            ),
            const SizedBox(height: 16),
            CurrencyInputField(
              label: _crossCurrency ? 'From amount' : 'Amount',
              currencies: active,
              selectedCurrency: _currencyFrom,
              initialAmount: _amountFrom,
              onAmountChanged: (v) => _amountFrom = v,
              onCurrencyChanged: (code) => setState(() => _currencyFrom = code),
            ),
            if (_crossCurrency) ...[
              const SizedBox(height: 16),
              CurrencyInputField(
                label: 'To amount',
                currencies: active,
                selectedCurrency: _currencyTo,
                initialAmount: _amountTo,
                onAmountChanged: (v) => _amountTo = v,
                onCurrencyChanged: (code) =>
                    setState(() => _currencyTo = code),
              ),
              if (_amountFrom != null &&
                  _amountTo != null &&
                  _amountFrom != Decimal.zero) ...[
                const SizedBox(height: 6),
                Text(
                  'Rate: 1 ${_currencyFrom!.value} = '
                  '${_displayRate(_amountFrom!, _amountTo!)} '
                  '${_currencyTo!.value}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              // Quietly let the user know that picking a different destination
              // currency below will unlock the cross-currency form.
              Text(
                'Pick a different destination currency to enter a custom rate.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<CurrencyCode>(
                initialValue: _currencyTo,
                decoration: const InputDecoration(labelText: 'To currency'),
                items: [
                  for (final c in active)
                    DropdownMenuItem(
                        value: c.code, child: Text(c.code.value)),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  setState(() => _currencyTo = code);
                },
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 24),
            DateChips(value: _date, onChanged: (d) => setState(() => _date = d)),
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Text(_saveError!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  String _displayRate(Decimal from, Decimal to) {
    final rate = (to / from).toDecimal(scaleOnInfinitePrecision: 6);
    return rate.toString();
  }
}

class _AccountTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Account? account;
  final VoidCallback onTap;

  const _AccountTile({
    required this.label,
    required this.icon,
    required this.account,
    required this.onTap,
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
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  Text(
                    account?.path ?? 'Tap to pick',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: account == null
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
