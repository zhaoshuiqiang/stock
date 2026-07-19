import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/widgets/score_breakdown_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(() => ScoringConfig.showCalibratedProbability = false);

  testWidgets('renders score, recommendation and dimension rows', (tester) async {
    await tester.pumpWidget(_wrap(const ScoreBreakdownCard(
      score: 7.0,
      recommendation: '买入',
      dimensionScores: {'趋势': 8.0, '反转动量': 5.0, '量价流': 6.0},
      calibrationByHorizon: null,
    )));
    expect(find.text('评分明细'), findsOneWidget);
    expect(find.textContaining('买入'), findsWidgets);
    expect(find.text('趋势'), findsOneWidget);
    expect(find.text('反转动量'), findsOneWidget);
  });

  testWidgets('hides calibration when flag is off', (tester) async {
    ScoringConfig.showCalibratedProbability = false;
    await tester.pumpWidget(_wrap(ScoreBreakdownCard(
      score: 7.0,
      recommendation: '买入',
      dimensionScores: {'趋势': 8.0},
      calibrationByHorizon: {
        3: CalibrationEstimate(
            horizon: 3,
            probability: 0.64,
            sampleCount: 180,
            wilsonLower: 0.57,
            wilsonUpper: 0.70),
      },
    )));
    expect(find.textContaining('历史校准胜率'), findsNothing);
  });

  testWidgets('shows calibration probability when flag is on', (tester) async {
    ScoringConfig.showCalibratedProbability = true;
    await tester.pumpWidget(_wrap(ScoreBreakdownCard(
      score: 8.0,
      recommendation: '强烈买入',
      dimensionScores: {'趋势': 8.0},
      calibrationByHorizon: {
        3: CalibrationEstimate(
            horizon: 3,
            probability: 0.64,
            sampleCount: 180,
            wilsonLower: 0.57,
            wilsonUpper: 0.70),
      },
    )));
    expect(find.textContaining('历史校准胜率'), findsOneWidget);
    expect(find.textContaining('64%'), findsWidgets);
  });

  testWidgets('renders nothing when dimensionScores is empty', (tester) async {
    await tester.pumpWidget(_wrap(const ScoreBreakdownCard(
      score: 5.0,
      recommendation: '观望',
      dimensionScores: null,
      calibrationByHorizon: null,
    )));
    expect(find.text('评分明细'), findsNothing);
  });
}
