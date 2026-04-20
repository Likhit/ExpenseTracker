import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/currency.dart';
import '../../../providers/storage_providers.dart';

class CurrencyListScreen extends ConsumerWidget {
  const CurrencyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currenciesAsync = ref.watch(currenciesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Currencies')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCurrencyDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: currenciesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (currencies) {
          if (currencies.isEmpty) {
            return const Center(child: Text('No currencies.'));
          }

          // Group by type
          final grouped = <CurrencyType, List<Currency>>{};
          for (final c in currencies) {
            grouped.putIfAbsent(c.type, () => []).add(c);
          }
          final types = grouped.keys.toList()
            ..sort((a, b) => a.index.compareTo(b.index));

          return ListView(
            children: types.expand((type) {
              final items = grouped[type]!
                ..sort((a, b) => a.code.compareTo(b.code));
              return [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    _typeLabel(type),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                ...items.map((c) => ListTile(
                      leading: CircleAvatar(
                        child: Text(c.symbol ?? c.code[0]),
                      ),
                      title: Text('${c.code} — ${c.name}'),
                      subtitle: Text('${c.decimalPlaces} decimal places'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showCurrencyDialog(context, ref, c);
                          } else if (action == 'delete') {
                            ref.read(currenciesProvider.notifier).remove(c);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    )),
              ];
            }).toList(),
          );
        },
      ),
    );
  }

  String _typeLabel(CurrencyType type) {
    switch (type) {
      case CurrencyType.fiat:
        return 'Fiat Currencies';
      case CurrencyType.stock:
        return 'Stocks';
      case CurrencyType.crypto:
        return 'Crypto';
      case CurrencyType.custom:
        return 'Custom';
    }
  }

  void _showCurrencyDialog(BuildContext context, WidgetRef ref,
      [Currency? existing]) {
    showDialog(
      context: context,
      builder: (_) => _CurrencyDialog(existing: existing, ref: ref),
    );
  }
}

class _CurrencyDialog extends StatefulWidget {
  final Currency? existing;
  final WidgetRef ref;

  const _CurrencyDialog({this.existing, required this.ref});

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _symbolController;
  late final TextEditingController _decimalController;
  late CurrencyType _type;

  @override
  void initState() {
    super.initState();
    _codeController =
        TextEditingController(text: widget.existing?.code ?? '');
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
    _symbolController =
        TextEditingController(text: widget.existing?.symbol ?? '');
    _decimalController = TextEditingController(
        text: (widget.existing?.decimalPlaces ?? 2).toString());
    _type = widget.existing?.type ?? CurrencyType.fiat;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _symbolController.dispose();
    _decimalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Currency' : 'New Currency'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code',
                hintText: 'e.g., USD, AAPL, BTC',
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g., US Dollar, Apple Inc.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CurrencyType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: CurrencyType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                            t.name[0].toUpperCase() + t.name.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symbolController,
              decoration: const InputDecoration(
                labelText: 'Symbol (optional)',
                hintText: r'e.g., $, €, ₿',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _decimalController,
              decoration: const InputDecoration(
                labelText: 'Decimal Places',
                hintText: '2 for fiat, 0 for stocks, 8 for crypto',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  void _save() {
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();
    if (code.isEmpty || name.isEmpty) return;

    final decimals = int.tryParse(_decimalController.text.trim()) ?? 2;
    final symbol = _symbolController.text.trim();
    final notifier = widget.ref.read(currenciesProvider.notifier);

    if (widget.existing != null) {
      notifier.edit(widget.existing!.copyWith(
        code: code,
        name: name,
        type: _type,
        symbol: symbol.isEmpty ? null : symbol,
        decimalPlaces: decimals,
      ));
    } else {
      notifier.add(Currency(
        id: const Uuid().v4(),
        code: code,
        name: name,
        type: _type,
        symbol: symbol.isEmpty ? null : symbol,
        decimalPlaces: decimals,
        createdAt: DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }
}
