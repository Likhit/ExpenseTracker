import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/ui/widgets/app_shell.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester, {required Size size}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump();
  }

  testWidgets('narrow widths use a bottom NavigationBar', (tester) async {
    await pumpShell(tester, size: const Size(360, 720));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Home is the initial destination.
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });

  testWidgets('wide widths use a side NavigationRail', (tester) async {
    await pumpShell(tester, size: const Size(1024, 768));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });

  testWidgets('tapping a destination switches the body', (tester) async {
    await pumpShell(tester, size: const Size(360, 720));

    // Tap the Accounts label in the NavigationBar.
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Accounts'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Home'), findsNothing);

    // And back to Home.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Home'), findsOneWidget);
  });
}
