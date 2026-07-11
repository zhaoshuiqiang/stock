import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/screens/sector_overview_screen.dart';

void main() {
  testWidgets('SectorOverviewScreen exposes ranking filters',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SectorOverviewScreen(autoLoad: false),
      ),
    );
    await tester.pump();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('上涨'), findsOneWidget);
    expect(find.text('下跌'), findsOneWidget);
  });
}
