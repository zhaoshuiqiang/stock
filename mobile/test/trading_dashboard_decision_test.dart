import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/widgets/short_term_decision_panel.dart';

void main() {
  testWidgets('renders four dimensions and selected horizon probability',
      (tester) async {
    final decision = ShortTermDecision(
      directionScore: 62,
      tradeQualityScore: 74,
      riskScore: 31,
      evidenceConfidence: 79,
      calibrationByHorizon: {
        3: CalibrationEstimate(
          horizon: 3,
          probability: 0.68,
          sampleCount: 120,
          wilsonLower: 0.59,
          wilsonUpper: 0.76,
        ),
      },
      direction: RecommendationDirection.bullish,
      marketRegime: MarketRegime.range,
      modelVersion: 'v2',
      rawComprehensiveScore: 7,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: ShortTermDecisionPanel(
            decision: decision,
            recommendation: RecommendationDecision(
              direction: RecommendationDirection.bullish,
              level: RecommendationLevel.bullish,
              label: '看多',
              legacyScore: 8,
              actionable: true,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('方向强度'), findsOneWidget);
    expect(find.text('交易质量'), findsOneWidget);
    expect(find.text('风险'), findsOneWidget);
    expect(find.text('证据置信'), findsOneWidget);
    expect(find.text('79/100'), findsOneWidget);
    await tester.tap(find.text('3日'));
    await tester.pump();
    expect(find.textContaining('68.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
