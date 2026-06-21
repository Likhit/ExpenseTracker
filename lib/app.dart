import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/ledger_provider.dart';
import 'services/ledger_state.dart';
import 'ui/screens/conflict_screen.dart';
import 'ui/screens/loading_screen.dart';
import 'ui/widgets/app_shell.dart';

/// Root of the app: a [MaterialApp] whose home gates on the async
/// [LedgerService] and its post-sync [LedgerState]. The Material 3 baseline
/// here is intentionally minimal — a swappable theme layer (Phase 2.5) lands
/// later.
class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
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
      themeMode: ThemeMode.system,
      home: const _RootGate(),
    );
  }
}

/// Decides what to show while/after [ledgerProvider] resolves: a loading
/// splash, an error message, the conflict screen when the post-startup sync
/// surfaced one, or the main [AppShell].
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
        return const AppShell();
      },
    );
  }
}
