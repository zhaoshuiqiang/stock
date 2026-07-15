import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/calibration_metrics.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
import 'package:stock_analyzer/widgets/decision_calibration_summary.dart';

void main() {
  testWidgets(
      'renders typed decision calibration metrics and insufficient data',
      (tester) async {
    const summary = DecisionStatisticsSummary(
      evaluatedCount: 40,
      pendingCount: 3,
      maturedPendingCount: 1,
      invalidCount: 2,
      rawHitWilson: ConfidenceInterval(0.48, 0.76),
      meanReturn: 1.2,
      medianReturn: 0.8,
      meanAlpha: 0.4,
      medianAlpha: 0.2,
      meanMfe: 2.5,
      meanMae: -1.1,
      calibration: DecisionCalibrationQuality(
        sampleCount: 12,
        signalDateCount: 4,
      ),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DecisionCalibrationSummary(summary: summary)),
    ));

    expect(find.text('Wilson 95%'), findsOneWidget);
    expect(find.text('平均收益'), findsOneWidget);
    expect(find.text('中位 Alpha'), findsOneWidget);
    expect(find.text('MFE'), findsOneWidget);
    expect(find.text('MAE'), findsOneWidget);
    expect(find.textContaining('样本不足'), findsNWidgets(2));
  });
}
