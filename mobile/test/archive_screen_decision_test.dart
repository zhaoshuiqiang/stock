import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
import 'package:stock_analyzer/widgets/decision_archive_summary.dart';

void main() {
  testWidgets('summary prioritizes effective alpha hits and separate counts',
      (tester) async {
    final summary = DecisionStatisticsSummary(
      evaluatedCount: 80,
      pendingCount: 12,
      maturedPendingCount: 5,
      invalidCount: 3,
      coverage: 80 / 88,
      rawHitRate: 0.62,
      effectiveHitRate: 0.58,
      alphaHitRate: 0.55,
      calibration: const DecisionCalibrationQuality(
        sampleCount: 40,
        signalDateCount: 12,
        brier: 0.21,
        ece: 0.08,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DecisionArchiveSummary(
          summary: summary,
          horizon: 3,
          onHorizonChanged: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('3日'), findsWidgets);
    expect(find.text('有效命中'), findsOneWidget);
    expect(find.text('Alpha命中'), findsOneWidget);
    expect(find.text('已评估 80'), findsOneWidget);
    expect(find.text('待评估 12'), findsOneWidget);
    expect(find.text('无效 3'), findsOneWidget);
  });
}
