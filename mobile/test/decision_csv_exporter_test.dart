import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/services/decision_csv_exporter.dart';

void main() {
  test('exports versioned dimensions and independent horizon outcomes', () {
    final snapshot = _snapshot();
    final csv = buildDecisionCsv([
      DecisionExportRow(
        snapshot: snapshot,
        outcomes: {
          1: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
          3: DecisionOutcomeRecord(
            snapshotId: 1,
            horizon: 3,
            status: DecisionOutcomeStatus.evaluated,
            dueTradeDate: DateTime(2026, 7, 18),
            entryTradeDate: DateTime(2026, 7, 16),
            targetTradeDate: DateTime(2026, 7, 18),
            forecastReturn: 1.2,
            executableReturn: 1.0,
            benchmarkReturn: 0.6,
            alphaReturn: 0.6,
            mfe: 2.1,
            mae: -0.4,
            rawDirectionHit: true,
            effectiveDirectionHit: true,
            alphaHit: true,
            executableValid: true,
            predictedProbability: 0.7,
            predictedSampleCount: 120,
            predictedWilsonLower: 0.61,
            predictedWilsonUpper: 0.78,
          ),
          5: DecisionOutcomeRecord(
            snapshotId: 1,
            horizon: 5,
            status: DecisionOutcomeStatus.invalid,
            invalidReason: '数据不足',
          ),
        },
      ),
    ]);
    expect(csv.startsWith('\ufeff'), isTrue);
    expect(csv, contains('app_version'));
    expect(csv, contains('is_retrospective'));
    expect(csv, contains('signal_time'));
    expect(csv, contains('evidence_trade_date'));
    expect(csv, contains('signal_phase'));
    expect(csv, contains('recommendation_level'));
    expect(csv, contains('actionable'));
    expect(csv, contains('recommendation_gates'));
    expect(csv, contains('model_version'));
    expect(csv, contains('direction_score'));
    expect(csv, contains('h3_due_trade_date'));
    expect(csv, contains('h3_target_trade_date'));
    expect(csv, contains('h3_forecast_return'));
    expect(csv, contains('h3_oriented_return'));
    expect(csv, contains('h3_oriented_executable_return'));
    expect(csv, contains('h3_executable_valid'));
    expect(csv, contains('h3_raw_hit'));
    expect(csv, contains('h3_effective_hit'));
    expect(csv, contains('h3_alpha_hit'));
    expect(csv, contains('h3_predicted_probability'));
    expect(csv, contains('3.31.20260716'));
    expect(csv, contains('preMarket'));
    expect(csv, contains('2026-07-15'));
    expect(csv, contains('strongBullish'));
    expect(csv, contains('risk_above_threshold'));
    expect(csv, contains('pending'));
    expect(csv, contains('invalid'));
    expect(csv, isNot(contains('pending,0')));
  });

  test('groups all outcome horizons by decision snapshot for export', () {
    final first = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final second = DecisionSnapshotRecord.minimalForTesting(
      id: 2,
      code: '000002',
      signalTradeDate: DateTime(2026, 7, 14),
    );

    final rows = buildDecisionExportRows([
      DecisionStatisticsRow(
        snapshot: first,
        outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      ),
      DecisionStatisticsRow(
        snapshot: first,
        outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 3),
      ),
      DecisionStatisticsRow(
        snapshot: second,
        outcome: DecisionOutcomeRecord(snapshotId: 2, horizon: 5),
      ),
    ]);

    expect(rows, hasLength(2));
    expect(rows.first.outcomes.keys, containsAll(<int>[1, 3]));
    expect(rows.last.outcomes.keys, contains(5));
  });

  test('neutral export clears legacy directional labels and excursions', () {
    final snapshot = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final csv = buildDecisionCsv([
      DecisionExportRow(
        snapshot: snapshot,
        outcomes: {
          1: DecisionOutcomeRecord(
            snapshotId: 1,
            horizon: 1,
            status: DecisionOutcomeStatus.evaluated,
            rawDirectionHit: true,
            effectiveDirectionHit: true,
            alphaHit: true,
            mfe: 0,
            mae: 0,
            predictedProbability: 0.9,
            predictedSampleCount: 100,
            predictedWilsonLower: 0.8,
            predictedWilsonUpper: 0.95,
          ),
        },
      ),
    ]);
    final lines = csv.split('\r\n');
    final headers = lines.first.replaceFirst('\ufeff', '').split(',');
    final values = lines[1].split(',');
    String valueOf(String header) => values[headers.indexOf(header)];

    expect(valueOf('h1_raw_hit'), isEmpty);
    expect(valueOf('h1_effective_hit'), isEmpty);
    expect(valueOf('h1_alpha_hit'), isEmpty);
    expect(valueOf('h1_mfe'), isEmpty);
    expect(valueOf('h1_mae'), isEmpty);
    expect(valueOf('h1_predicted_probability'), isEmpty);
    expect(valueOf('h1_predicted_sample_count'), isEmpty);
    expect(valueOf('h1_wilson_lower'), isEmpty);
    expect(valueOf('h1_wilson_upper'), isEmpty);
  });

  test('uses a distinct filename prefix for decision exports', () {
    expect(
      decisionExportFileName(DateTime(2026, 7, 15, 9, 8, 7)),
      'decision_export_20260715_090807.csv',
    );
  });
}

DecisionSnapshotRecord _snapshot() => DecisionSnapshotRecord(
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
      directionScore: 60,
      tradeQualityScore: 70,
      riskScore: 25,
      evidenceConfidence: 80,
      recommendationLevel: 'strongBullish',
      recommendationLabel: '强看多',
      legacyScore: 9,
      actionable: true,
      recommendationGates: const ['risk_above_threshold'],
      marketRegime: MarketRegime.bullishTrend,
      marketChangePct: 0.8,
      modelVersion: 'short-term-v3',
      appVersion: '3.31.20260716',
      primaryStrategyId: 'trend_follow',
      primaryStrategyName: '趋势跟随',
      supportingStrategyIds: const ['volume_confirm'],
      directionComponents: const {'trend': 0.7},
      qualityComponents: const {'timing': 0.8},
      riskComponents: const {'volatility': 0.2},
      dataQualityFlags: const ['verified'],
      createdAt: DateTime(2026, 7, 16, 8, 45),
    );
