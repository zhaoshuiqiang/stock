import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_score_diagnostics.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/widgets/decision_archive_summary.dart';
import 'package:stock_analyzer/widgets/decision_score_diagnostics_panel.dart';
import 'package:stock_analyzer/widgets/decision_snapshot_provenance_card.dart';

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
      bullishSampleCount: 50,
      bullishEffectiveHitRate: 0.6,
      bearishSampleCount: 20,
      bearishEffectiveHitRate: 0.5,
      balancedEffectiveHitRate: 0.55,
      neutralSampleCount: 10,
      neutralStabilityRate: 0.7,
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
    expect(find.text('看多命中'), findsOneWidget);
    expect(find.text('看空命中'), findsOneWidget);
    expect(find.text('多空平衡'), findsOneWidget);
    expect(find.text('多50 / 空20'), findsOneWidget);
    expect(find.text('中性稳定'), findsOneWidget);
    expect(find.text('Alpha命中'), findsOneWidget);
    expect(find.text('已评估 80'), findsOneWidget);
    expect(find.text('待评估 12'), findsOneWidget);
    expect(find.text('无效 3'), findsOneWidget);
  });

  testWidgets('diagnostic panel remains readable at 360 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final diagnostics = DecisionScoreDiagnostics.analyze(const []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DecisionScoreDiagnosticsPanel(diagnostics: diagnostics),
        ),
      ),
    ));

    expect(find.text('方向分布'), findsOneWidget);
    expect(find.text('评分梯度'), findsOneWidget);
    expect(find.text('五维相关性'), findsOneWidget);
    expect(find.text('调权准备度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail provenance shows evidence phase actionability and gates',
      (tester) async {
    final snapshot = DecisionSnapshotRecord(
      id: 1,
      code: '000001',
      name: '平安银行',
      source: 'archive',
      signalTime: DateTime(2026, 7, 16, 8, 45),
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 15),
      signalPhase: DecisionSignalPhase.preMarket,
      signalPrice: 10,
      benchmarkCode: '000300',
      direction: RecommendationDirection.bullish,
      directionScore: 40,
      tradeQualityScore: 70,
      riskScore: 25,
      evidenceConfidence: 80,
      recommendationLevel: 'strongBullish',
      recommendationLabel: '强看多',
      legacyScore: 9,
      actionable: false,
      recommendationGates: const ['critical_data_missing'],
      marketRegime: MarketRegime.range,
      modelVersion: 'short-term-v3',
      appVersion: '3.31.20260716',
      dataQualityFlags: const ['market_context_missing'],
      createdAt: DateTime(2026, 7, 16, 8, 45),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DecisionSnapshotProvenanceCard(snapshot: snapshot)),
    ));

    expect(find.textContaining('strongBullish'), findsOneWidget);
    expect(find.textContaining('不可执行'), findsOneWidget);
    expect(find.textContaining('盘前'), findsOneWidget);
    expect(find.textContaining('证据日 2026-07-15'), findsOneWidget);
    expect(find.textContaining('信号日 2026-07-16'), findsOneWidget);
    expect(find.textContaining('critical_data_missing'), findsOneWidget);
    expect(find.textContaining('market_context_missing'), findsOneWidget);
  });
}
