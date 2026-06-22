import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/providers/ledger_provider.dart';
import 'package:expense_tracker/services/ledger_service.dart';

/// Pumps [child] under a [ProviderScope] whose [ledgerProvider] resolves to a
/// freshly constructed [LedgerService] over a temp directory. The directory and
/// the service are torn down automatically when the test ends.
///
/// Real disk I/O (creating the temp dir, opening the JSONL files, seeding) is
/// wrapped in [WidgetTester.runAsync] — widget tests run under a fake clock by
/// default, so plain `await` on real I/O would deadlock.
///
/// Returns the live [LedgerService] so tests can seed it directly (skipping the
/// UI) before exercising widgets.
Future<LedgerService> pumpWithLedger(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 1200),
  Future<void> Function(LedgerService ledger)? seed,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  late final Directory dir;
  late final LedgerService ledger;
  await tester.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('expense_tracker_ui_');
    ledger = await LedgerService.create(
      accountsPath: '${dir.path}/accounts.jsonl',
      categoriesPath: '${dir.path}/categories.jsonl',
      currenciesPath: '${dir.path}/currencies.jsonl',
      transactionsPath: '${dir.path}/transactions.jsonl',
    );
    if (seed != null) await seed(ledger);
  });
  addTearDown(() async {
    await ledger.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ledgerProvider.overrideWith((ref) async => ledger),
      ],
      child: MaterialApp(home: child),
    ),
  );
  await drain(tester);
  return ledger;
}

/// Drains pending real-async work (provider futures, engine writes) and pumps
/// frames so any newly-yielded async provider values get rendered. Use after
/// triggering an action that touches the engine (e.g. tapping a save button).
Future<void> drain(WidgetTester tester) async {
  // Real-async tick lets file I/O (started by stream providers during the
  // previous pump) complete on the actual Dart event loop. Then `pump` rebuilds
  // any widgets whose providers just yielded a new value. Several passes cover
  // chains of dependent providers (ledger → currencies → currenciesByCode,
  // ledger → accounts → balances) and the post-write notification path
  // (ledger.changes → stream re-yield → frame).
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}
