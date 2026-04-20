import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:decimal/decimal.dart';

import '../../../models/transaction.dart';
import '../../../models/leg.dart';
import '../../../models/currency.dart';
import '../../../providers/storage_providers.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/account_picker.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  final TransactionType type;

  const TransactionFormScreen({super.key, required this.type});

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState
    extends ConsumerState<TransactionFormScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _toAmountController = TextEditingController();

  String? _categoryPath;
  String? _accountId;
  String? _fromAccountId;
  String? _toAccountId;
  String _currencyCode = 'USD';
  String _toCurrencyCode = 'USD';
  DateTime _date = DateTime.now();

  String get _title {
    switch (widget.type) {
      case TransactionType.expense:
        return 'Add Expense';
      case TransactionType.income:
        return 'Add Income';
      case TransactionType.transfer:
        return 'Add Transfer';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _toAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currenciesAsync = ref.watch(currenciesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: currenciesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (currencies) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date
              _DateField(
                date: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: 16),

              // Amount + Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CurrencyDropdown(
                      currencies: currencies,
                      value: _currencyCode,
                      onChanged: (v) => setState(() => _currencyCode = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Type-specific fields
              if (widget.type == TransactionType.transfer)
                _buildTransferFields(currencies)
              else
                _buildSimpleFields(),

              const SizedBox(height: 16),

              // Description
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleFields() {
    final parentType = widget.type == TransactionType.income
        ? TransactionType.income
        : TransactionType.expense;

    return Column(
      children: [
        CategoryPicker(
          parentType: parentType,
          initialPath: _categoryPath,
          onSelected: (path) => setState(() => _categoryPath = path),
        ),
        const SizedBox(height: 16),
        AccountPicker(
          selectedAccountId: _accountId,
          onSelected: (a) => setState(() => _accountId = a.id),
          label: widget.type == TransactionType.income
              ? 'To Account'
              : 'From Account',
        ),
      ],
    );
  }

  Widget _buildTransferFields(List<Currency> currencies) {
    return Column(
      children: [
        AccountPicker(
          selectedAccountId: _fromAccountId,
          onSelected: (a) => setState(() => _fromAccountId = a.id),
          label: 'From Account',
        ),
        const SizedBox(height: 16),
        AccountPicker(
          selectedAccountId: _toAccountId,
          onSelected: (a) => setState(() => _toAccountId = a.id),
          label: 'To Account',
        ),
        const SizedBox(height: 16),

        // Destination amount + currency (for cross-currency transfers)
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _toAmountController,
                decoration: const InputDecoration(
                  labelText: 'Destination Amount',
                  helperText: 'Leave empty if same currency',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CurrencyDropdown(
                currencies: currencies,
                value: _toCurrencyCode,
                onChanged: (v) => setState(() => _toCurrencyCode = v),
              ),
            ),
          ],
        ),

        if (_toAmountController.text.isNotEmpty &&
            _currencyCode != _toCurrencyCode)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ExchangeRateDisplay(
              fromAmount: _amountController.text,
              toAmount: _toAmountController.text,
              fromCurrency: _currencyCode,
              toCurrency: _toCurrencyCode,
            ),
          ),
      ],
    );
  }

  Future<void> _save() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _showError('Please enter an amount');
      return;
    }

    final amount = Decimal.tryParse(amountText);
    if (amount == null || amount <= Decimal.zero) {
      _showError('Please enter a valid amount');
      return;
    }

    switch (widget.type) {
      case TransactionType.expense:
        await _saveExpense(amount);
      case TransactionType.income:
        await _saveIncome(amount);
      case TransactionType.transfer:
        await _saveTransfer(amount);
    }
  }

  Future<void> _saveExpense(Decimal amount) async {
    if (_categoryPath == null) {
      _showError('Please select a category');
      return;
    }
    if (_accountId == null) {
      _showError('Please select an account');
      return;
    }

    // Ensure category exists (creates if new)
    await ref
        .read(categoriesProvider.notifier)
        .findOrCreate(_categoryPath!, TransactionType.expense);

    final tx = Transaction(
      id: const Uuid().v4(),
      date: _date,
      description: _descriptionController.text.trim(),
      type: TransactionType.expense,
      legs: [
        Leg(
          accountId: _accountId!,
          amount: '-${amount.toString()}',
          currencyCode: _currencyCode,
        ),
        Leg(
          accountId: _accountId!,
          amount: amount.toString(),
          currencyCode: _currencyCode,
          categoryPath: _categoryPath,
        ),
      ],
      createdAt: DateTime.now(),
    );

    if (!_validateAndSave(tx)) return;
    await ref.read(transactionsProvider.notifier).add(tx);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveIncome(Decimal amount) async {
    if (_categoryPath == null) {
      _showError('Please select a category');
      return;
    }
    if (_accountId == null) {
      _showError('Please select an account');
      return;
    }

    await ref
        .read(categoriesProvider.notifier)
        .findOrCreate(_categoryPath!, TransactionType.income);

    final tx = Transaction(
      id: const Uuid().v4(),
      date: _date,
      description: _descriptionController.text.trim(),
      type: TransactionType.income,
      legs: [
        Leg(
          accountId: _accountId!,
          amount: amount.toString(),
          currencyCode: _currencyCode,
        ),
        Leg(
          accountId: _accountId!,
          amount: '-${amount.toString()}',
          currencyCode: _currencyCode,
          categoryPath: _categoryPath,
        ),
      ],
      createdAt: DateTime.now(),
    );

    if (!_validateAndSave(tx)) return;
    await ref.read(transactionsProvider.notifier).add(tx);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveTransfer(Decimal amount) async {
    if (_fromAccountId == null) {
      _showError('Please select source account');
      return;
    }
    if (_toAccountId == null) {
      _showError('Please select destination account');
      return;
    }

    final toAmountText = _toAmountController.text.trim();
    final isCrossCurrency =
        toAmountText.isNotEmpty && _currencyCode != _toCurrencyCode;

    final toAmount = isCrossCurrency
        ? Decimal.tryParse(toAmountText)
        : amount;

    if (toAmount == null || toAmount <= Decimal.zero) {
      _showError('Please enter a valid destination amount');
      return;
    }

    final effectiveToCurrency =
        isCrossCurrency ? _toCurrencyCode : _currencyCode;

    Map<String, dynamic>? metadata;
    if (isCrossCurrency) {
      // rate = toAmount / fromAmount (how many destination units per source unit)
      final rate = (toAmount / amount).toDouble();
      final inverse = (amount / toAmount).toDouble();
      metadata = {
        'exchangeRate': {
          'from': _currencyCode,
          'to': effectiveToCurrency,
          'rate': rate,
          'inverse': inverse,
        },
      };
    }

    final tx = Transaction(
      id: const Uuid().v4(),
      date: _date,
      description: _descriptionController.text.trim(),
      type: TransactionType.transfer,
      legs: [
        Leg(
          accountId: _fromAccountId!,
          amount: '-${amount.toString()}',
          currencyCode: _currencyCode,
        ),
        Leg(
          accountId: _toAccountId!,
          amount: toAmount.toString(),
          currencyCode: effectiveToCurrency,
        ),
      ],
      metadata: metadata,
      createdAt: DateTime.now(),
    );

    if (!_validateAndSave(tx)) return;
    await ref.read(transactionsProvider.notifier).add(tx);
    if (mounted) Navigator.pop(context);
  }

  bool _validateAndSave(Transaction tx) {
    final ledger = ref.read(ledgerServiceProvider);
    final result = ledger.validate(tx);
    if (!result.isValid) {
      _showError(result.errorMessage!);
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _DateField({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          prefixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}

class _CurrencyDropdown extends StatelessWidget {
  final List<Currency> currencies;
  final String value;
  final ValueChanged<String> onChanged;

  const _CurrencyDropdown({
    required this.currencies,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: currencies.any((c) => c.code == value) ? value : null,
      decoration: const InputDecoration(labelText: 'Currency'),
      items: currencies
          .map((c) => DropdownMenuItem(
                value: c.code,
                child: Text(c.code),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ExchangeRateDisplay extends StatelessWidget {
  final String fromAmount;
  final String toAmount;
  final String fromCurrency;
  final String toCurrency;

  const _ExchangeRateDisplay({
    required this.fromAmount,
    required this.toAmount,
    required this.fromCurrency,
    required this.toCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final from = Decimal.tryParse(fromAmount);
    final to = Decimal.tryParse(toAmount);

    if (from == null || to == null || from == Decimal.zero) {
      return const SizedBox.shrink();
    }

    final rate = (to / from).toDecimal().toStringAsFixed(6);

    return Text(
      '1 $fromCurrency = $rate $toCurrency',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
    );
  }
}
