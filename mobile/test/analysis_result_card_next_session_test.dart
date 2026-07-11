import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/widgets/analysis_result_card.dart';

void main() {
  testWidgets('AnalysisResultCard displays next-session prediction',
      (WidgetTester tester) async {
    final analysis = AnalysisResult(
      recommendation: '谨慎买入',
      score: 6,
      riskLevel: '中等',
      confidenceScore: 0.62,
      nextDayPrediction: const {
        'next_session': {
          'next_open_up_probability': 0.55,
          'next_close_up_probability': 0.63,
          'downside_risk_probability': 0.31,
          'confidence': 0.58,
          'sample_count': 18,
          'scenario_tags': ['强势延续'],
          'risk_warnings': [],
        },
      },
    );
    expect(analysis.nextDayPrediction, isNotNull);
    expect(analysis.nextDayPrediction!.containsKey('next_session'), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisResultCard(analysis: analysis),
        ),
      ),
    );

    expect(find.text('次交易预测'), findsOneWidget);
    expect(find.textContaining('收盘上涨 63%'), findsOneWidget);
    expect(find.textContaining('样本 18'), findsOneWidget);
  });
}
