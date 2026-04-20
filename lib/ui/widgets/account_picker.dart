import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../models/account.dart';
import '../../providers/storage_providers.dart';

class AccountPicker extends ConsumerWidget {
  final String? selectedAccountId;
  final ValueChanged<Account> onSelected;
  final String label;

  const AccountPicker({
    super.key,
    this.selectedAccountId,
    required this.onSelected,
    this.label = 'Account',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return accountsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Error: $e'),
      data: (accounts) {
        if (accounts.isEmpty) {
          return const Text('No accounts. Create one first.');
        }

        // Group accounts by their top-level group
        final grouped = groupBy(accounts, (Account a) => a.group);
        return DropdownButtonFormField<String>(
          initialValue: selectedAccountId,
          decoration: InputDecoration(labelText: label),
          hint: const Text('Select account'),
          items: grouped.entries.expand((entry) {
            final group = entry.key;
            final groupAccounts = entry.value;

            if (groupAccounts.length == 1 &&
                !groupAccounts.first.path.contains('::')) {
              return [
                DropdownMenuItem(
                  value: groupAccounts.first.id,
                  child: Text(groupAccounts.first.path),
                ),
              ];
            }

            return [
              DropdownMenuItem(
                enabled: false,
                value: '__header_$group',
                child: Text(
                  group,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ...groupAccounts.map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Text(a.displayName),
                    ),
                  )),
            ];
          }).toList(),
          onChanged: (id) {
            if (id == null || id.startsWith('__header_')) return;
            final account = accounts.firstWhere((a) => a.id == id);
            onSelected(account);
          },
          selectedItemBuilder: (context) {
            // Build flat list matching items order for selected display
            final items = <Widget>[];
            for (final entry in grouped.entries) {
              final group = entry.key;
              final groupAccounts = entry.value;
              if (groupAccounts.length == 1 &&
                  !groupAccounts.first.path.contains('::')) {
                items.add(Text(groupAccounts.first.path));
              } else {
                items.add(Text(group)); // header placeholder
                for (final a in groupAccounts) {
                  items.add(Text(a.path));
                }
              }
            }
            return items;
          },
        );
      },
    );
  }
}
