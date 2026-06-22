import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/account.dart';
import '../../models/ids.dart';
import '../../providers/ledger_provider.dart';

const _uuid = Uuid();

/// User-creatable subset of [AccountType]. The income/expense types are
/// reserved for the two built-in accounts created by `LedgerService.create`,
/// so they're never offered here.
const _userTypes = [
  AccountType.asset,
  AccountType.liability,
  AccountType.equity,
];

/// Dialog for creating a new account or editing an existing one. Returns the
/// saved [Account] via [Navigator.pop] on success, or null if cancelled.
class AccountEditDialog extends ConsumerStatefulWidget {
  /// Existing account, or null for a new one.
  final Account? existing;

  const AccountEditDialog({this.existing, super.key});

  static Future<Account?> show(BuildContext context, {Account? existing}) {
    return showDialog<Account>(
      context: context,
      builder: (_) => AccountEditDialog(existing: existing),
    );
  }

  @override
  ConsumerState<AccountEditDialog> createState() => _AccountEditDialogState();
}

class _AccountEditDialogState extends ConsumerState<AccountEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _path;
  late final TextEditingController _notes;
  late AccountType _type;
  late bool _isVirtual;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _path = TextEditingController(text: existing?.path ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _type = existing?.type ?? AccountType.asset;
    _isVirtual = existing?.isVirtual ?? false;
  }

  @override
  void dispose() {
    _path.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _validatePath(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Path is required';
    if (value.startsWith('::') || value.endsWith('::')) {
      return 'Path cannot start or end with "::"';
    }
    if (value.contains(':::')) return 'Path cannot contain ":::"';
    final segments = value.split('::');
    if (segments.any((s) => s.isEmpty)) {
      return 'Path segments cannot be empty';
    }
    final existing = widget.existing;
    final accounts = ref.read(accountsProvider).value ?? const [];
    final clash = accounts.any((a) =>
        !a.deleted &&
        a.path == value &&
        (existing == null || a.id != existing.id));
    if (clash) return 'An account with this path already exists';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final now = DateTime.now();
    final account = existing == null
        ? Account(
            id: AccountId(_uuid.v4()),
            path: _path.text.trim(),
            type: _type,
            isVirtual: _isVirtual,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            createdAt: now,
          )
        : existing.copyWith(
            path: _path.text.trim(),
            type: _type,
            isVirtual: _isVirtual,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            updatedAt: now,
          );
    final ledger = await ref.read(ledgerProvider.future);
    final result = await ledger.save(account);
    if (!mounted) return;
    if (!result.isValid) {
      setState(() => _saveError = result.errorMessage);
      return;
    }
    Navigator.of(context).pop(account);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit account' : 'New account'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _path,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Path',
                  hintText: 'Chase::Checking',
                  helperText: 'Use :: to nest accounts.',
                ),
                validator: _validatePath,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AccountType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in _userTypes)
                    DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Virtual'),
                subtitle: const Text(
                    'Mark as a placeholder account (e.g. for tracking-only buckets).'),
                value: _isVirtual,
                onChanged: (v) => setState(() => _isVirtual = v),
              ),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional',
                ),
                minLines: 1,
                maxLines: 3,
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

String _typeLabel(AccountType t) => switch (t) {
      AccountType.asset => 'Asset',
      AccountType.liability => 'Liability',
      AccountType.equity => 'Equity',
      AccountType.income => 'Income',
      AccountType.expense => 'Expense',
    };
