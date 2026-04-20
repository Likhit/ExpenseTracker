import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import '../../../models/account.dart';
import '../../../providers/storage_providers.dart';

class AccountListScreen extends ConsumerWidget {
  const AccountListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAccountDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(
              child: Text('No accounts yet. Tap + to add one.'),
            );
          }
          return _AccountGroupedList(accounts: accounts);
        },
      ),
    );
  }

  void _showAccountDialog(BuildContext context, WidgetRef ref,
      [Account? existing]) {
    showDialog(
      context: context,
      builder: (_) => _AccountDialog(existing: existing, ref: ref),
    );
  }
}

class _AccountGroupedList extends ConsumerWidget {
  final List<Account> accounts;
  const _AccountGroupedList({required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by the first segment of the path
    final grouped = groupBy(accounts, (Account a) => a.group);
    final groups = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final groupAccounts = grouped[group]!;

        // If the group has only one account and its path has no separator,
        // show it directly without a group header.
        if (groupAccounts.length == 1 &&
            !groupAccounts.first.path.contains('::')) {
          final account = groupAccounts.first;
          return _AccountTile(account: account);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                group,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...groupAccounts.map((a) => _AccountTile(account: a)),
          ],
        );
      },
    );
  }
}

class _AccountTile extends ConsumerWidget {
  final Account account;
  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeLabel = account.type.name[0].toUpperCase() +
        account.type.name.substring(1);

    return ListTile(
      leading: Icon(_iconForAccountType(account.type)),
      title: Text(account.displayName),
      subtitle: Text(
        [typeLabel, if (account.isVirtual) 'Virtual'].join(' · '),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          if (action == 'edit') {
            showDialog(
              context: context,
              builder: (_) =>
                  _AccountDialog(existing: account, ref: ref),
            );
          } else if (action == 'delete') {
            ref.read(accountsProvider.notifier).remove(account);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  IconData _iconForAccountType(AccountType type) {
    switch (type) {
      case AccountType.asset:
        return Icons.account_balance;
      case AccountType.liability:
        return Icons.credit_card;
      case AccountType.income:
        return Icons.arrow_downward;
      case AccountType.expense:
        return Icons.arrow_upward;
      case AccountType.equity:
        return Icons.balance;
    }
  }
}

class _AccountDialog extends StatefulWidget {
  final Account? existing;
  final WidgetRef ref;

  const _AccountDialog({this.existing, required this.ref});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _pathController;
  late final TextEditingController _notesController;
  late AccountType _type;
  late bool _isVirtual;

  @override
  void initState() {
    super.initState();
    _pathController =
        TextEditingController(text: widget.existing?.path ?? '');
    _notesController =
        TextEditingController(text: widget.existing?.notes ?? '');
    _type = widget.existing?.type ?? AccountType.asset;
    _isVirtual = widget.existing?.isVirtual ?? false;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Account' : 'New Account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Path',
                hintText: 'e.g., Chase::Checking',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: AccountType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                            t.name[0].toUpperCase() + t.name.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Virtual Account'),
              subtitle: const Text('e.g., Tax Account'),
              value: _isVirtual,
              onChanged: (v) => setState(() => _isVirtual = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
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
    final path = _pathController.text.trim();
    if (path.isEmpty) return;

    final notifier = widget.ref.read(accountsProvider.notifier);

    if (widget.existing != null) {
      notifier.edit(widget.existing!.copyWith(
        path: path,
        type: _type,
        isVirtual: _isVirtual,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ));
    } else {
      notifier.add(Account(
        id: const Uuid().v4(),
        path: path,
        type: _type,
        isVirtual: _isVirtual,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }
}
