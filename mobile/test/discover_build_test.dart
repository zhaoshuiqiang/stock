import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';

void main() {
  testWidgets('DiscoverScreen builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DiscoverScreen(),
    ));
    // Allow async initState callbacks to settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // If we reach here without exception, the build is OK
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });
}
