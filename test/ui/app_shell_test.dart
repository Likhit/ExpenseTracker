import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/ui/widgets/app_shell.dart';

import 'test_harness.dart';

void main() {
  testWidgets('narrow widths use a bottom NavigationBar', (tester) async {
    await pumpWithLedger(tester, const AppShell(), size: const Size(360, 720));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });

  testWidgets('wide widths use a side NavigationRail', (tester) async {
    await pumpWithLedger(tester, const AppShell(),
        size: const Size(1024, 768));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });

  testWidgets('tapping a destination switches the body', (tester) async {
    await pumpWithLedger(tester, const AppShell(), size: const Size(360, 720));

    await tester.tap(find.widgetWithText(NavigationDestination, 'Accounts'));
    await drain(tester);
    expect(find.widgetWithText(AppBar, 'Accounts'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Home'), findsNothing);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
    await drain(tester);
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });
}
