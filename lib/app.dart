import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/ledger_provider.dart';
import 'providers/settings_provider.dart';
import 'services/app_settings.dart';
import 'services/ledger_state.dart';
import 'ui/screens/conflict_screen.dart';
import 'ui/screens/loading_screen.dart';
import 'ui/screens/onboarding/onboarding_screen.dart';
import 'ui/widgets/app_shell.dart';

/// Root of the app: a [MaterialApp] whose home gates on the async
/// [LedgerService] and its post-sync [LedgerState], and whose `themeMode`
/// follows the persisted [AppSettings].
class ExpenseTrackerApp extends ConsumerWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    final themeMode = ref.watch(
      settingsProvider.select(
        (s) => (s.value?.themeMode ?? AppThemeMode.system).toFlutter(),
      ),
    );
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      home: const _RootGate(),
    );
  }
}

/// Maps the storage-layer [AppThemeMode] onto Flutter's [ThemeMode].
extension AppThemeModeX on AppThemeMode {
  ThemeMode toFlutter() => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

/// Decides what to show while/after [ledgerProvider] resolves: a loading
/// splash, an error message, the conflict screen when the post-startup sync
/// surfaced one, the onboarding wizard on first launch, or the main [AppShell].
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    return ledger.when(
      loading: () => const LoadingScreen(),
      error: (err, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load ledger:\n$err',
                textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (service) {
        final state = ref.watch(ledgerStateProvider).value ?? service.state;
        if (state is LedgerConflicted) {
          return ConflictScreen(conflictCount: state.conflicts.length);
        }
        // First-launch gate: show onboarding until it's marked complete.
        final onboarded = ref.watch(
          settingsProvider.select((s) => s.value?.onboardingComplete ?? false),
        );
        if (!onboarded) return const OnboardingScreen();
        return const AppShell();
      },
    );
  }
}
