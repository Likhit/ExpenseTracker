import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/currency.dart';
import '../../providers/ledger_provider.dart';
import '../widgets/currency_edit_dialog.dart';

/// Currencies list, grouped by [CurrencyType] (Fiat / Stock / Crypto). The
/// `Code` is the unique key — same edit/soft-delete pattern as accounts.
class CurrenciesScreen extends ConsumerStatefulWidget {
  const CurrenciesScreen({super.key});

  @override
  ConsumerState<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends ConsumerState<CurrenciesScreen> {
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    final currenciesAsync = ref.watch(currenciesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Currencies'),
        actions: [
          IconButton(
            icon: Icon(_showDeleted
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            tooltip: _showDeleted ? 'Hide deleted' : 'Show deleted',
            onPressed: () => setState(() => _showDeleted = !_showDeleted),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CurrencyEditDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New currency'),
      ),
      body: currenciesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load currencies: $e')),
        data: (all) =>
            _CurrencyList(currencies: all, showDeleted: _showDeleted),
      ),
    );
  }
}

class _CurrencyList extends ConsumerWidget {
  final List<Currency> currencies;
  final bool showDeleted;

  const _CurrencyList({required this.currencies, required this.showDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = [
      for (final c in currencies)
        if (showDeleted || !c.deleted) c,
    ]..sort((a, b) => a.code.value.compareTo(b.code.value));

    if (visible.isEmpty) return const _EmptyCurrencies();

    final byType = <CurrencyType, List<Currency>>{};
    for (final c in visible) {
      byType.putIfAbsent(c.type, () => []).add(c);
    }

    // Group sections in a fixed order: Fiat, Stock, Crypto.
    const order = [CurrencyType.fiat, CurrencyType.stock, CurrencyType.crypto];

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final type in order)
          if (byType[type] != null) ...[
            _SectionHeader(label: _typeLabel(type)),
            for (final c in byType[type]!) _CurrencyTile(currency: c),
          ],
      ],
    );
  }
}

class _CurrencyTile extends ConsumerWidget {
  final Currency currency;

  const _CurrencyTile({required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final deleted = currency.deleted;
    final titleStyle = deleted
        ? theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          )
        : theme.textTheme.bodyLarge;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Text(
          currency.symbol ?? currency.code.value.substring(0, 1),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      title: Text('${currency.code.value} · ${currency.name}', style: titleStyle),
      subtitle: Text(
          '${currency.decimalPlaces} '
          '${currency.decimalPlaces == 1 ? 'decimal place' : 'decimal places'}'
          '${currency.symbol != null ? ' · ${currency.symbol}' : ''}'),
      trailing: PopupMenuButton<_CurrencyAction>(
        onSelected: (action) => _handle(context, ref, action),
        itemBuilder: (_) => [
          if (!deleted)
            const PopupMenuItem(
              value: _CurrencyAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
              ),
            ),
          if (!deleted)
            const PopupMenuItem(
              value: _CurrencyAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          if (deleted)
            const PopupMenuItem(
              value: _CurrencyAction.restore,
              child: ListTile(
                leading: Icon(Icons.restore),
                title: Text('Restore'),
              ),
            ),
        ],
      ),
      onTap: deleted
          ? null
          : () => CurrencyEditDialog.show(context, existing: currency),
    );
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, _CurrencyAction action) async {
    switch (action) {
      case _CurrencyAction.edit:
        await CurrencyEditDialog.show(context, existing: currency);
      case _CurrencyAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete currency?'),
            content: Text(
                'Soft-delete "${currency.code.value}". Existing legs still '
                'reference it by code, so amounts continue to render.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (confirmed != true) return;
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.delete(currency);
      case _CurrencyAction.restore:
        final ledger = await ref.read(ledgerProvider.future);
        await ledger.save(
            currency.copyWith(deleted: false, updatedAt: DateTime.now()));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EmptyCurrencies extends StatelessWidget {
  const _EmptyCurrencies();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.currency_exchange_outlined, size: 56),
            const SizedBox(height: 16),
            Text('No currencies yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add one to start entering transactions. Common fiats are seeded '
              'on first launch — if you cleared them, tap "New currency".',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _typeLabel(CurrencyType t) => switch (t) {
      CurrencyType.fiat => 'Fiat',
      CurrencyType.stock => 'Stock',
      CurrencyType.crypto => 'Crypto',
    };

enum _CurrencyAction { edit, delete, restore }
