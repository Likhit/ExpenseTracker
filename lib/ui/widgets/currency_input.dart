import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/currency.dart';
import '../../models/ids.dart';

/// Decimal amount input paired with a currency selector. Returns the typed
/// value as a [Decimal] via [onAmountChanged] and the picked currency code via
/// [onCurrencyChanged]. The input mask is computed from the selected
/// currency's `decimalPlaces`, so an integer-only currency (JPY) won't accept
/// a fractional part.
class CurrencyInputField extends StatefulWidget {
  final String label;
  final Decimal? initialAmount;
  final CurrencyCode? selectedCurrency;
  final List<Currency> currencies;
  final ValueChanged<Decimal?> onAmountChanged;
  final ValueChanged<CurrencyCode> onCurrencyChanged;
  final String? errorText;

  const CurrencyInputField({
    required this.label,
    required this.currencies,
    required this.onAmountChanged,
    required this.onCurrencyChanged,
    this.initialAmount,
    this.selectedCurrency,
    this.errorText,
    super.key,
  });

  @override
  State<CurrencyInputField> createState() => _CurrencyInputFieldState();
}

class _CurrencyInputFieldState extends State<CurrencyInputField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialAmount?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Currency? get _currency {
    final code = widget.selectedCurrency;
    if (code == null) return null;
    for (final c in widget.currencies) {
      if (c.code == code) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = _currency;
    final decimals = currency?.decimalPlaces ?? 2;
    final allow = decimals == 0
        ? RegExp(r'[0-9]')
        : RegExp(r'[0-9.]');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _controller,
            keyboardType: TextInputType.numberWithOptions(
                decimal: decimals > 0),
            inputFormatters: [
              FilteringTextInputFormatter.allow(allow),
              _DecimalLimitFormatter(maxFractionDigits: decimals),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: '0.${'0' * (decimals == 0 ? 0 : decimals)}',
              errorText: widget.errorText,
            ),
            style: theme.textTheme.titleLarge,
            onChanged: (raw) => widget.onAmountChanged(_parse(raw)),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: DropdownButtonFormField<CurrencyCode>(
            initialValue: widget.selectedCurrency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final c in widget.currencies)
                DropdownMenuItem(
                    value: c.code, child: Text(c.code.value)),
            ],
            onChanged: (code) {
              if (code == null) return;
              widget.onCurrencyChanged(code);
              setState(() {}); // Re-evaluate decimal mask.
            },
          ),
        ),
      ],
    );
  }

  Decimal? _parse(String raw) {
    if (raw.isEmpty || raw == '.') return null;
    return Decimal.tryParse(raw);
  }
}

/// Caps the number of digits after the decimal point. A maxFractionDigits of
/// 0 forbids the decimal point entirely (the upstream filter already strips
/// it).
class _DecimalLimitFormatter extends TextInputFormatter {
  final int maxFractionDigits;

  _DecimalLimitFormatter({required this.maxFractionDigits});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final dot = text.indexOf('.');
    if (dot < 0) return newValue;
    final fraction = text.length - dot - 1;
    if (fraction <= maxFractionDigits) return newValue;
    return oldValue;
  }
}
