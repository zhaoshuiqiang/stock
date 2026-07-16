import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('summary separates statuses denominators and return statistics', () {
    final rows = [
      _row(
          direction: RecommendationDirection.bullish,
          status: DecisionOutcomeStatus.evaluated,
          forecast: 2,
          alpha: 1,
          rawHit: true,
          effectiveHit: true,
          alphaHit: true,
          mfe: 3,
          mae: -1),
      _row(
          direction: RecommendationDirection.bearish,
          status: DecisionOutcomeStatus.evaluated,
          forecast: -1,
          alpha: -2,
          rawHit: false,
          effectiveHit: false,
          alphaHit: false,
          mfe: 1,
          mae: -3),
      _row(status: DecisionOutcomeStatus.invalid),
      _row(
          status: DecisionOutcomeStatus.pending,
          dueDate: DateTime(2026, 7, 14)),
      _row(
          status: DecisionOutcomeStatus.pending,
          dueDate: DateTime(2026, 7, 20)),
    ];
    final summary = DecisionStatistics.summarize(
      rows,
      now: DateTime(2026, 7, 15),
    );
    expect(summary.evaluatedCount, 2);
    expect(summary.invalidCount, 1);
    expect(summary.pendingCount, 2);
    expect(summary.maturedPendingCount, 1);
    expect(summary.coverage, 0.5);
    expect(summary.rawHitRate, 0.5);
    expect(summary.effectiveHitRate, 0.5);
    expect(summary.alphaHitRate, 0.5);
    expect(summary.meanReturn, 0.5);
    expect(summary.medianReturn, 0.5);
    expect(summary.meanAlpha, -0.5);
    expect(summary.meanMfe, 2);
    expect(summary.meanMae, -2);
  });

  test('same-day pending outcome matures only after market close', () {
    final rows = [
      _row(
        status: DecisionOutcomeStatus.pending,
        dueDate: DateTime(2026, 7, 15),
      ),
    ];

    expect(
      DecisionStatistics.summarize(
        rows,
        now: DateTime(2026, 7, 15, 8, 45),
      ).maturedPendingCount,
      0,
    );
    expect(
      DecisionStatistics.summarize(
        rows,
        now: DateTime(2026, 7, 15, 15),
      ).maturedPendingCount,
      1,
    );
  });

  test('summary uses independent direction denominators and oriented returns',
      () {
    final rows = [
      _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        forecast: 2,
        alpha: 1,
        effectiveHit: true,
        alphaHit: true,
      ),
      _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        forecast: -1,
        alpha: -2,
        effectiveHit: false,
        alphaHit: false,
      ),
      _row(
        direction: RecommendationDirection.bearish,
        status: DecisionOutcomeStatus.evaluated,
        forecast: -3,
        alpha: -1.5,
        effectiveHit: true,
        alphaHit: true,
      ),
      _row(
        direction: RecommendationDirection.neutral,
        status: DecisionOutcomeStatus.evaluated,
        alpha: 0.4,
      ),
      _row(
        direction: RecommendationDirection.neutral,
        status: DecisionOutcomeStatus.evaluated,
        alpha: 0.8,
      ),
    ];

    final summary = DecisionStatistics.summarize(rows);

    expect(summary.bullishSampleCount, 2);
    expect(summary.bullishEffectiveHitRate, 0.5);
    expect(summary.bearishSampleCount, 1);
    expect(summary.bearishEffectiveHitRate, 1);
    expect(summary.balancedEffectiveHitRate, 0.75);
    expect(summary.neutralSampleCount, 2);
    expect(summary.neutralStabilityRate, 0.5);
    expect(summary.orientedSampleCount, 3);
    expect(summary.meanOrientedReturn, closeTo(4 / 3, 1e-9));
    expect(summary.medianOrientedReturn, 2);
    expect(summary.meanOrientedAlpha, closeTo(1 / 6, 1e-9));
    expect(summary.medianOrientedAlpha, 1);
  });

  test('legacy neutral hit fields do not enter directional statistics', () {
    final summary = DecisionStatistics.summarize([
      _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        rawHit: true,
        effectiveHit: true,
        alphaHit: true,
        predicted: 0.7,
        mfe: 3,
        mae: -1,
      ),
      _row(
        direction: RecommendationDirection.neutral,
        status: DecisionOutcomeStatus.evaluated,
        alpha: 0.1,
        rawHit: true,
        effectiveHit: true,
        alphaHit: true,
        predicted: 0.9,
        mfe: 0,
        mae: 0,
        snapshotId: 2,
      ),
    ]);

    expect(summary.rawHitSampleCount, 1);
    expect(summary.effectiveHitSampleCount, 1);
    expect(summary.alphaHitSampleCount, 1);
    expect(summary.calibration.sampleCount, 1);
    expect(summary.meanMfe, 3);
    expect(summary.meanMae, -1);
  });

  test('calibration quality requires 30 outcomes and 10 signal dates', () {
    final insufficientSamples = List.generate(
      29,
      (i) => _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        predicted: 0.7,
        effectiveHit: i < 20,
        signalDate: DateTime(2026, 1, 1 + i % 10),
      ),
    );
    expect(DecisionStatistics.summarize(insufficientSamples).calibration.brier,
        isNull);

    final insufficientDates = List.generate(
      30,
      (i) => _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        predicted: 0.7,
        effectiveHit: i < 20,
        signalDate: DateTime(2026, 1, 1 + i % 9),
      ),
    );
    expect(DecisionStatistics.summarize(insufficientDates).calibration.brier,
        isNull);

    final enough = List.generate(
      30,
      (i) => _row(
        direction: RecommendationDirection.bullish,
        status: DecisionOutcomeStatus.evaluated,
        predicted: 0.7,
        effectiveHit: i < 21,
        signalDate: DateTime(2026, 1, 1 + i % 10),
      ),
    );
    final quality = DecisionStatistics.summarize(enough).calibration;
    expect(quality.sampleCount, 30);
    expect(quality.brier, isNotNull);
    expect(quality.ece, isNotNull);
  });
}

DecisionStatisticsRow _row({
  required DecisionOutcomeStatus status,
  RecommendationDirection direction = RecommendationDirection.neutral,
  double directionScore = 0,
  Map<String, double> directionComponents = const {},
  double? forecast,
  double? alpha,
  bool? rawHit,
  bool? effectiveHit,
  bool? alphaHit,
  double? mfe,
  double? mae,
  double? predicted,
  DateTime? dueDate,
  DateTime? signalDate,
  int snapshotId = 1,
  int horizon = 1,
  MarketRegime marketRegime = MarketRegime.range,
}) {
  final date = signalDate ?? DateTime(2026, 1, 1);
  return DecisionStatisticsRow(
    snapshot: DecisionSnapshotRecord(
      id: snapshotId,
      code: '000001',
      source: 'test',
      signalTime: date,
      signalTradeDate: date,
      evidenceTradeDate: date,
      signalPrice: 10,
      benchmarkCode: '000300',
      direction: direction,
      directionScore: directionScore,
      tradeQualityScore: 50,
      riskScore: 50,
      evidenceConfidence: 50,
      recommendationLevel: 'test',
      recommendationLabel: '测试',
      legacyScore: 5,
      marketRegime: marketRegime,
      modelVersion: 'short-term-v3',
      directionComponents: directionComponents,
      createdAt: date,
    ),
    outcome: DecisionOutcomeRecord(
      id: 1,
      snapshotId: snapshotId,
      horizon: horizon,
      status: status,
      dueTradeDate: dueDate,
      forecastReturn: forecast,
      alphaReturn: alpha,
      rawDirectionHit: rawHit,
      effectiveDirectionHit: effectiveHit,
      alphaHit: alphaHit,
      mfe: mfe,
      mae: mae,
      predictedProbability: predicted,
    ),
  );
}
