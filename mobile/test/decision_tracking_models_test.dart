import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('decision snapshot round trips typed fields and JSON components', () {
    final record = DecisionSnapshotRecord(
      id: 7,
      code: '600519',
      name: '贵州茅台',
      source: 'explore',
      signalTime: DateTime(2026, 7, 14, 14, 55),
      signalTradeDate: DateTime(2026, 7, 14),
      evidenceTradeDate: DateTime(2026, 7, 11),
      signalPhase: DecisionSignalPhase.preMarket,
      signalPrice: 1500,
      adjustedSignalPrice: 1498,
      benchmarkCode: '000300',
      sectorName: '白酒',
      direction: RecommendationDirection.bullish,
      directionScore: 72,
      tradeQualityScore: 81,
      riskScore: 28,
      evidenceConfidence: 76,
      recommendationLevel: 'bullish',
      recommendationLabel: '看多',
      legacyScore: 8,
      actionable: true,
      recommendationGates: const ['liquidity_gate'],
      marketRegime: MarketRegime.bullishTrend,
      marketChangePct: 0.8,
      modelVersion: 'short-term-v2',
      appVersion: '3.31.20260716',
      isRetrospective: true,
      primaryStrategyId: 'trend_pullback',
      primaryStrategyName: '趋势回踩',
      supportingStrategyIds: const ['volume_confirm'],
      directionComponents: const {'technical': 42},
      qualityComponents: const {'liquidity': 18},
      riskComponents: const {'volatility': 12},
      dataQualityFlags: const ['fresh_quote'],
      createdAt: DateTime(2026, 7, 14, 15),
    );

    final map = record.toMap();
    expect(map['signal_trade_date'], '2026-07-14');
    expect(map['evidence_trade_date'], '2026-07-11');
    expect(map['signal_phase'], 'preMarket');
    expect(map['actionable'], 1);
    expect(map['recommendation_gates_json'], '["liquidity_gate"]');
    expect(map['is_retrospective'], 1);
    expect(map['supporting_strategy_ids_json'], '["volume_confirm"]');

    final restored = DecisionSnapshotRecord.fromMap(map);
    expect(restored.signalTradeDate, DateTime(2026, 7, 14));
    expect(restored.evidenceTradeDate, DateTime(2026, 7, 11));
    expect(restored.signalPhase, DecisionSignalPhase.preMarket);
    expect(restored.actionable, isTrue);
    expect(restored.recommendationGates, ['liquidity_gate']);
    expect(restored.appVersion, '3.31.20260716');
    expect(restored.isRetrospective, isTrue);
    expect(restored.direction, RecommendationDirection.bullish);
    expect(restored.marketRegime, MarketRegime.bullishTrend);
    expect(restored.primaryStrategyId, 'trend_pullback');
    expect(restored.supportingStrategyIds, ['volume_confirm']);
    expect(restored.directionComponents, {'technical': 42.0});
    expect(restored.dataQualityFlags, ['fresh_quote']);
  });

  test('legacy snapshot maps receive safe provenance defaults', () {
    final record = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final legacy = Map<String, dynamic>.from(record.toMap())
      ..remove('evidence_trade_date')
      ..remove('signal_phase')
      ..remove('actionable')
      ..remove('recommendation_gates_json')
      ..remove('app_version')
      ..remove('is_retrospective');

    final restored = DecisionSnapshotRecord.fromMap(legacy);

    expect(restored.evidenceTradeDate, restored.signalTradeDate);
    expect(restored.signalPhase, DecisionSignalPhase.unknown);
    expect(restored.actionable, isFalse);
    expect(restored.recommendationGates, isEmpty);
    expect(restored.appVersion, isEmpty);
    expect(restored.isRetrospective, isFalse);
  });

  test('decision outcome round trips dates nullable booleans and prediction',
      () {
    final outcome = DecisionOutcomeRecord(
      id: 3,
      snapshotId: 7,
      horizon: 3,
      status: DecisionOutcomeStatus.evaluated,
      dueTradeDate: DateTime(2026, 7, 17),
      entryTradeDate: DateTime(2026, 7, 15),
      targetTradeDate: DateTime(2026, 7, 17),
      rawDirectionHit: true,
      effectiveDirectionHit: false,
      alphaHit: null,
      corporateActionDetected: true,
      executableValid: false,
      predictedProbability: 0.68,
      predictedSampleCount: 42,
      predictedWilsonLower: 0.53,
      predictedWilsonUpper: 0.79,
      predictionCreatedAt: DateTime(2026, 7, 14, 15),
    );

    final map = outcome.toMap();
    expect(map['due_trade_date'], '2026-07-17');
    expect(map['raw_direction_hit'], 1);
    expect(map['effective_direction_hit'], 0);
    expect(map['alpha_hit'], isNull);

    final restored = DecisionOutcomeRecord.fromMap(map);
    expect(restored.status, DecisionOutcomeStatus.evaluated);
    expect(restored.dueTradeDate, DateTime(2026, 7, 17));
    expect(restored.rawDirectionHit, isTrue);
    expect(restored.effectiveDirectionHit, isFalse);
    expect(restored.alphaHit, isNull);
    expect(restored.predictedProbability, 0.68);
  });

  test('evaluation work item exposes snapshot and pending outcome', () {
    final snapshot = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final outcome = DecisionOutcomeRecord(
      id: 2,
      snapshotId: 1,
      horizon: 1,
    );

    final item = DecisionEvaluationWorkItem(
      snapshot: snapshot,
      outcome: outcome,
    );
    expect(item.snapshot.code, '000001');
    expect(item.outcome.status, DecisionOutcomeStatus.pending);
  });

  test('tracking records reject unsupported horizons', () {
    expect(
      () => DecisionOutcomeRecord(snapshotId: 1, horizon: 2),
      throwsArgumentError,
    );
  });
}
