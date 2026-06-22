import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/currency.dart';
import '../../models/ids.dart';
import '../../providers/ledger_provider.dart';

const _uuid = Uuid();

/// Dialog for creating or editing a [Currency]. Code is the unique key (so
/// it is uppercase-normalized and locked on edit — renaming the canonical
/// identifier would break every leg that referenced it).
class CurrencyEditDialog extends ConsumerStatefulWidget {
  final Currency? existing;

  const CurrencyEditDialog({this.existing, super.key});

  static Future<Currency?> show(BuildContext context, {Currency? existing}) {
    return showDialog<Currency>(
      context: context,
      builder: (_) => CurrencyEditDialog(existing: existing),
    );
  }

  @override
  ConsumerState<CurrencyEditDialog> createState() =>
      _CurrencyEditDialogState();
}

class _CurrencyEditDialogState extends ConsumerState<CurrencyEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _symbol;
  late CurrencyType _type;
  late int _decimalPlaces;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _code = TextEditingController(text: existing?.code.value ?? '');
    _name = TextEditingController(text: existing?.name ?? '');
    _symbol = TextEditingController(text: existing?.symbol ?? '');
    _type = existing?.type ?? CurrencyType.fiat;
    _decimalPlaces = existing?.decimalPlaces ?? 2;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _symbol.dispose();
    super.dispose();
  }

  String? _validateCode(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    if (value.isEmpty) return 'Code is required';
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value)) {
      return 'Code can only contain letters and digits';
    }
    final existing = widget.existing;
    if (existing != null) return null; // Code locked on edit.
    final currencies = ref.read(currenciesProvider).value ?? const [];
    final clash = currencies
        .any((c) => !c.deleted && c.code.value.toUpperCase() == value);
    if (clash) return 'A currency with this code already exists';
    return null;
  }

  String? _validateName(String? raw) {
    if ((raw ?? '').trim().isEmpty) return 'Name is required';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final now = DateTime.now();
    final code = CurrencyCode(_code.text.trim().toUpperCase());
    final symbol = _symbol.text.trim();
    final currency = existing == null
        ? Currency(
            id: CurrencyId(_uuid.v4()),
            code: code,
            name: _name.text.trim(),
            type: _type,
            symbol: symbol.isEmpty ? null : symbol,
            decimalPlaces: _decimalPlaces,
            createdAt: now,
          )
        : existing.copyWith(
            name: _name.text.trim(),
            type: _type,
            symbol: symbol.isEmpty ? null : symbol,
            decimalPlaces: _decimalPlaces,
            updatedAt: now,
          );
    final ledger = await ref.read(ledgerProvider.future);
    final result = await ledger.save(currency);
    if (!mounted) return;
    if (!result.isValid) {
      setState(() => _saveError = result.errorMessage);
      return;
    }
    Navigator.of(context).pop(currency);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit currency' : 'New currency'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _code,
                autofocus: !isEdit,
                enabled: !isEdit,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'USD, EUR, AAPL, BTC, …',
                  helperText: 'Unique identifier. Locked once created.',
                ),
                validator: _validateCode,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _validateName,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CurrencyType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in CurrencyType.values)
                    DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _symbol,
                decoration: const InputDecoration(
                  labelText: 'Symbol',
                  hintText: '\$, €, ₿, … (optional)',
                ),
              ),
              const SizedBox(height: 16),
              _DecimalPlacesPicker(
                value: _decimalPlaces,
                onChanged: (v) => setState(() => _decimalPlaces = v),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(_saveError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _DecimalPlacesPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _DecimalPlacesPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Decimal places', style: theme.textTheme.bodyMedium),
              Text(
                _exampleFor(value),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.remove),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 36,
          child: Center(child: Text('$value',
              style: theme.textTheme.titleMedium)),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.add),
          onPressed: value < 12 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  String _exampleFor(int n) {
    if (n == 0) return 'Example: 1234';
    return 'Example: 1234.${'5' * n}';
  }
}

String _typeLabel(CurrencyType t) => switch (t) {
      CurrencyType.fiat => 'Fiat',
      CurrencyType.stock => 'Stock',
      CurrencyType.crypto => 'Crypto',
    };
