import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/widgets/skeleton_loader.dart';

void main() {
  testWidgets('SkeletonLoader builds and animates without error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SkeletonLoader()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SkeletonLoader), findsOneWidget);
  });

  testWidgets('SkeletonList renders the requested number of lines',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SkeletonList(lines: 4)),
    ));
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsNWidgets(4));
  });
}
