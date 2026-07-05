import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/account.dart';
import '../../../models/currency.dart';
import '../../../models/ids.dart';
import '../../../providers/ledger_provider.dart';
import '../../../providers/settings_provider.dart';

const _uuid = Uuid();

/// First-launch setup wizard (UX-spec "First-launch flow"): welcome → sync
/// folder → default currency → first account → land on Home. Every step is
/// skippable — defaults are reasonable and the same choices live in Settings.
///
/// Completion is recorded via [Settings.completeOnboarding], which flips the
/// gate in `_RootGate` so the [AppShell] takes over.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  static const _lastStep = 3;

  // First-account form state.
  final _accountName = TextEditingController(text: 'Checking');
  AccountType _accountType = AccountType.asset;
  bool _busy = false;

  @override
  void dispose() {
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    // Create the starter account if the user left a name in place.
    final name = _accountName.text.trim();
    if (name.isNotEmpty) {
      final ledger = await ref.read(ledgerProvider.future);
      await ledger.save(Account(
        id: AccountId(_uuid.v4()),
        path: name,
        type: _accountType,
        createdAt: DateTime.now(),
      ));
    }
    await ref.read(settingsProvider.notifier).completeOnboarding();
    // The gate rebuilds into the shell; nothing else to navigate.
  }

  Future<void> _skip() async {
    await ref.read(settingsProvider.notifier).completeOnboarding();
  }

  void _next() {
    if (_step < _lastStep) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final steps = <Widget>[
      const _WelcomeStep(),
      const _SyncFolderStep(),
      const _CurrencyStep(),
      _FirstAccountStep(
        nameController: _accountName,
        type: _accountType,
        onTypeChanged: (t) => setState(() => _accountType = t),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('Skip setup'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepDots(count: steps.length, current: _step),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(child: steps[_step]),
              ),
            ),
            _NavBar(
              step: _step,
              lastStep: _lastStep,
              busy: _busy,
              onBack: _step == 0 ? null : _back,
              onNext: _step == _lastStep ? _finish : _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int step;
  final int lastStep;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _NavBar({
    required this.step,
    required this.lastStep,
    required this.busy,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          if (onBack != null)
            TextButton(onPressed: busy ? null : onBack, child: const Text('Back')),
          const Spacer(),
          FilledButton(
            onPressed: busy ? null : onNext,
            child: Text(step == lastStep ? 'Finish' : 'Continue'),
          ),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int count;
  final int current;

  const _StepDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.savings_outlined, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Track every rupee, dollar, and coin',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'A private, offline-first ledger for your income, expenses, and '
          'investments. Your data stays in plain files you own — optionally '
          'synced through a folder of your choice.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          "We'll set up a sync folder, a default currency, and your first "
          'account. You can skip any of this and change it later in Settings.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SyncFolderStep extends ConsumerWidget {
  const _SyncFolderStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folder = ref.watch(
      settingsProvider.select((s) => s.value?.syncFolder),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where should your data live?',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Pick a folder inside Google Drive, OneDrive, or Syncthing to sync '
          'across devices — the app writes append-only JSONL files there. Or '
          'keep everything local to this device for now.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(folder ?? 'Local only (this device)'),
            subtitle: Text(folder == null
                ? 'Stored in the app data directory'
                : 'Sync folder'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Choose a sync folder',
                );
                if (picked != null) {
                  await ref.read(settingsProvider.notifier).setSyncFolder(picked);
                }
              },
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: const Text('Choose sync folder'),
            ),
            if (folder != null)
              TextButton(
                onPressed: () =>
                    ref.read(settingsProvider.notifier).setSyncFolder(null),
                child: const Text('Use local only'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CurrencyStep extends ConsumerWidget {
  const _CurrencyStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const [];
    final active = [
      for (final c in currencies)
        if (!c.deleted) c,
    ]..sort((a, b) => a.code.value.compareTo(b.code.value));
    final selected = ref.watch(
      settingsProvider.select((s) => s.value?.defaultCurrencyCode),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Default currency', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Used as the starting currency for new transactions. Common '
          'currencies are ready to go — add stocks or crypto later in Settings.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No currencies available yet.'),
          )
        else
          RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setDefaultCurrency(v),
            child: Column(
              children: [
                for (final c in active)
                  RadioListTile<String>(
                    value: c.code.value,
                    title: Text('${c.code.value} · ${c.name}'),
                    secondary: _CurrencyBadge(currency: c),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final Currency currency;

  const _CurrencyBadge({required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundColor: theme.colorScheme.onSecondaryContainer,
      child: Text(currency.symbol ?? currency.code.value.substring(0, 1)),
    );
  }
}

class _FirstAccountStep extends StatelessWidget {
  final TextEditingController nameController;
  final AccountType type;
  final ValueChanged<AccountType> onTypeChanged;

  const _FirstAccountStep({
    required this.nameController,
    required this.type,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Users only ever create asset/liability/equity accounts — income and
    // expense are the reserved built-ins.
    const selectable = [
      AccountType.asset,
      AccountType.liability,
      AccountType.equity,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your first account', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Add the account you spend from most — a bank account, a card, or '
          'cash. You can add more any time.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Account name',
            hintText: 'Checking',
            helperText: 'Leave blank to skip creating an account',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AccountType>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final t in selectable)
              DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
          ],
          onChanged: (t) {
            if (t != null) onTypeChanged(t);
          },
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
