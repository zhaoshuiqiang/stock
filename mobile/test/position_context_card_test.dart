import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/widgets/position_context_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders position advice, dynamic stop and monetized risk when held',
      (tester) async {
    await tester.pumpWidget(_wrap(const PositionContextCard(
      score: 8,
      currentPrice: 12,
      avgPrice: 10,
      quantity: 100,
      atr: 0.3,
      riskScore: 40,
    )));
    expect(find.text('持仓建议'), findsOneWidget);
    expect(find.text('可加仓'), findsOneWidget); // score>=7 and price>stop
    expect(find.text('动态止损位'), findsOneWidget);
    expect(find.text('预估风险回撤'), findsOneWidget);
  });

  testWidgets('hidden when the stock is not held (quantity 0)', (tester) async {
    await tester.pumpWidget(_wrap(const PositionContextCard(
      score: 8,
      currentPrice: 12,
      avgPrice: 0,
      quantity: 0,
      atr: 0.3,
      riskScore: 40,
    )));
    expect(find.text('持仓建议'), findsNothing);
  });

  testWidgets('shows stop-triggered advice when price at/below dynamic stop',
      (tester) async {
    // avg 10, peak ~10.2, atr 0.1 -> stop ~ max(9.2, 10.2-0.2)=10.0; price 9.8 <= stop
    await tester.pumpWidget(_wrap(const PositionContextCard(
      score: 9,
      currentPrice: 9.8,
      avgPrice: 10,
      quantity: 100,
      atr: 0.05,
      riskScore: 60,
    )));
    expect(find.text('触发止损'), findsOneWidget);
  });
}
