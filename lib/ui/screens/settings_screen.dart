import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ledger_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/app_settings.dart';
import 'categories_screen.dart';
import 'currencies_screen.dart';

/// Settings hub. Sync folder, default currency, and theme are edited here;
/// Categories and Currencies deep-link to their management screens.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    // Keep currencies warm so the default-currency picker (which reads them
    // synchronously on tap) always has a loaded list.
    ref.watch(currenciesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Sync folder'),
            subtitle: Text(settings.syncFolder ?? 'Local only (this device)'),
            onTap: () => _editSyncFolder(context, ref, settings),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Force re-sync'),
            subtitle: const Text('Re-scan the folder and merge conflict copies'),
            onTap: () => _forceResync(context, ref),
          ),
          const Divider(),
          const _SectionHeader('Preferences'),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Default currency'),
            subtitle: Text(settings.defaultCurrencyCode ?? 'Not set'),
            onTap: () => _editDefaultCurrency(context, ref, settings),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            onTap: () => _editTheme(context, ref, settings),
          ),
          const Divider(),
          const _SectionHeader('Manage'),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Edit the expense and income hierarchies'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange_outlined),
            title: const Text('Currencies'),
            subtitle: const Text('Fiat, stocks, and crypto'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSyncFolder(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final action = await showModalBottomSheet<_SyncFolderAction>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: const Text('Choose sync folder…'),
              onTap: () =>
                  Navigator.pop(context, _SyncFolderAction.choose),
            ),
            if (settings.syncFolder != null)
              ListTile(
                leading: const Icon(Icons.phonelink_off_outlined),
                title: const Text('Use local only'),
                onTap: () =>
                    Navigator.pop(context, _SyncFolderAction.local),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    final notifier = ref.read(settingsProvider.notifier);
    switch (action) {
      case _SyncFolderAction.choose:
        final picked = await FilePicker.getDirectoryPath(
            dialogTitle: 'Choose a sync folder');
        if (picked != null) await notifier.setSyncFolder(picked);
      case _SyncFolderAction.local:
        await notifier.setSyncFolder(null);
    }
  }

  Future<void> _forceResync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ledger = await ref.read(ledgerProvider.future);
    await ledger.sync();
    messenger.showSnackBar(const SnackBar(content: Text('Sync complete')));
  }

  Future<void> _editDefaultCurrency(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final currencies = ref.read(currenciesProvider).value ?? const [];
    final active = [
      for (final c in currencies)
        if (!c.deleted) c,
    ]..sort((a, b) => a.code.value.compareTo(b.code.value));

    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: RadioGroup<String>(
          groupValue: settings.defaultCurrencyCode,
          onChanged: (v) => Navigator.pop(context, v),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text('Default currency',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final c in active)
                RadioListTile<String>(
                  value: c.code.value,
                  title: Text('${c.code.value} · ${c.name}'),
                ),
            ],
          ),
        ),
      ),
    );
    if (code != null) {
      await ref.read(settingsProvider.notifier).setDefaultCurrency(code);
    }
  }

  Future<void> _editTheme(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final mode = await showDialog<AppThemeMode>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          RadioGroup<AppThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(
                    value: m,
                    title: Text(_themeLabel(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mode != null) {
      await ref.read(settingsProvider.notifier).setThemeMode(mode);
    }
  }
}

String _themeLabel(AppThemeMode m) => switch (m) {
      AppThemeMode.system => 'System',
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
    };

enum _SyncFolderAction { choose, local }

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

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
