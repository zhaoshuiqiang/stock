import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/widgets/limit_up_card.dart';

void main() {
  group('LimitUpCard', () {
    testWidgets('displays consecutive days badge and name', (tester) async {
      final a = LimitUpAnalysis(
        code: '600519', name: '贵州茅台', consecutiveDays: 3,
        boardType: '一字板', timeGrade: '竞价涨停',
        sealAmount: 23000, qualityScore: 8.5, premiumProb: 0.75,
        sector: '白酒', price: 1689.5, changePct: 10.0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: false,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.textContaining('3'), findsWidgets);
      expect(find.text('贵州茅台'), findsOneWidget);
      expect(find.textContaining('一字板'), findsOneWidget);
    });

    testWidgets('empty sector does not crash', (tester) async {
      final a = LimitUpAnalysis(code: '000001', name: 'X');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: false,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('watched state shows filled star', (tester) async {
      final a = LimitUpAnalysis(code: '000001', name: 'Test');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: true,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('unwatched state shows border star', (tester) async {
      final a = LimitUpAnalysis(code: '000001', name: 'Test');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: false,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });
  });
}
