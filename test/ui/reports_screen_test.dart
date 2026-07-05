import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/ui/screens/reports_screen.dart';

void main() {
  group('ReportsScreen hub', () {
    testWidgets('renders a card for each report', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));

      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Income vs expense'), findsOneWidget);
      expect(find.text('Net worth trend'), findsOneWidget);
      expect(find.text('Account balances'), findsOneWidget);
      expect(find.text('Budgets'), findsOneWidget);
    });

    testWidgets('tapping a card navigates to its drilldown', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));

      await tester.tap(find.text('Spending by category'));
      await tester.pumpAndSettle();

      // The placeholder detail screen shows the report title in its app bar.
      expect(find.widgetWithText(AppBar, 'Spending by category'),
          findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
    });
  });
}
