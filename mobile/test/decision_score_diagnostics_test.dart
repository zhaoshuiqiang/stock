import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_score_diagnostics.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('score bucket boundaries follow V3 strength semantics', () {
    expect(DecisionScoreDiagnostics.bucketFor(11.999), isNull);
    expect(DecisionScoreDiagnostics.bucketFor(12), DecisionScoreBucket.watch);
    expect(
        DecisionScoreDiagnostics.bucketFor(19.999), DecisionScoreBucket.watch);
    expect(
        DecisionScoreDiagnostics.bucketFor(20), DecisionScoreBucket.cautious);
    expect(DecisionScoreDiagnostics.bucketFor(34.999),
        DecisionScoreBucket.cautious);
    expect(DecisionScoreDiagnostics.bucketFor(35), DecisionScoreBucket.clear);
    expect(
        DecisionScoreDiagnostics.bucketFor(54.999), DecisionScoreBucket.clear);
    expect(DecisionScoreDiagnostics.bucketFor(55), DecisionScoreBucket.strong);
    expect(
        DecisionScoreDiagnostics.bucketFor(-100), DecisionScoreBucket.strong);
  });

  test('spearman uses average ranks for ties and rejects degenerate inputs',
      () {
    expect(
      DecisionScoreDiagnostics.spearman(
        const [1, 1, 2, 3],
        const [1, 2, 2, 4],
      ),
      closeTo(5 / 6, 1e-9),
    );
    expect(DecisionScoreDiagnostics.spearman(const [], const []), isNull);
    expect(
      DecisionScoreDiagnostics.spearman(
        const [1, 1, 1],
        const [1, 2, 3],
      ),
      isNull,
    );
  });

  test('signed score and all five components correlate with raw return', () {
    final rows = List.generate(30, (index) {
      final bullish = index < 15;
      final magnitude = 20.0 + index % 15;
      final sign = bullish ? 1.0 : -1.0;
      final component = sign * magnitude / 100;
      return _row(
        id: index + 1,
        signalDate: DateTime(2026, 1, 1 + index % 10),
        direction: bullish
            ? RecommendationDirection.bullish
            : RecommendationDirection.bearish,
        directionScore: sign * magnitude,
        forecastReturn: sign * magnitude / 10,
        effectiveHit: true,
        directionComponents: {
          trendComponentKey: component,
          reversalMomentumComponentKey: component,
          volumeFlowComponentKey: component,
          relativeStrengthComponentKey: component,
          nextSessionComponentKey: component,
        },
      );
    });

    final result = DecisionScoreDiagnostics.analyze(rows);

    expect(result.scoreCorrelation.sampleCount, 30);
    expect(result.scoreCorrelation.signalDateCount, 10);
    expect(result.scoreCorrelation.coefficient, closeTo(1, 1e-9));
    for (final key in const [
      trendComponentKey,
      reversalMomentumComponentKey,
      volumeFlowComponentKey,
      relativeStrengthComponentKey,
      nextSessionComponentKey,
    ]) {
      expect(result.componentCorrelations[key]!.coefficient, closeTo(1, 1e-9));
    }
  });

  test('correlations require both 30 mature samples and 10 signal dates', () {
    final only29 = List.generate(
      29,
      (index) => _correlationRow(index, dateCount: 10),
    );
    final only9Dates = List.generate(
      30,
      (index) => _correlationRow(index, dateCount: 9),
    );

    expect(
      DecisionScoreDiagnostics.analyze(only29).scoreCorrelation.coefficient,
      isNull,
    );
    expect(
      DecisionScoreDiagnostics.analyze(only9Dates).scoreCorrelation.coefficient,
      isNull,
    );
  });

  test('direction distribution warns only when one direction exceeds 70%', () {
    final rows = <DecisionStatisticsRow>[
      for (var i = 0; i < 8; i++)
        _row(id: i + 1, direction: RecommendationDirection.bullish),
      _row(id: 9, direction: RecommendationDirection.neutral),
      _row(id: 10, direction: RecommendationDirection.bearish),
    ];

    final distribution = DecisionScoreDiagnostics.analyze(rows).distribution;

    expect(distribution.bullishCount, 8);
    expect(distribution.bullishRatio, 0.8);
    expect(distribution.isBiased, isTrue);
    expect(distribution.biasedDirection, RecommendationDirection.bullish);
  });

  test('bucket statistics orient bearish return and alpha', () {
    final result = DecisionScoreDiagnostics.analyze([
      _row(
        id: 1,
        direction: RecommendationDirection.bearish,
        directionScore: -25,
        forecastReturn: -2,
        alphaReturn: -1,
        effectiveHit: true,
        alphaHit: true,
      ),
    ]);
    final bucket = result.bucket(
      RecommendationDirection.bearish,
      DecisionScoreBucket.cautious,
    );

    expect(bucket.sampleCount, 1);
    expect(bucket.effectiveHitRate, 1);
    expect(bucket.meanOrientedReturn, 2);
    expect(bucket.meanOrientedAlpha, 1);
  });

  test('monotonicity requires 20 samples and 5 dates in adjacent buckets', () {
    final eligible = <DecisionStatisticsRow>[
      ..._bucketRows(score: 15, count: 20, dateCount: 5, hitCount: 10),
      ..._bucketRows(score: 25, count: 20, dateCount: 5, hitCount: 15),
    ];
    final eligibleResult =
        DecisionScoreDiagnostics.analyze(eligible).bullishMonotonicity;
    expect(eligibleResult.eligiblePairCount, 1);
    expect(eligibleResult.isMonotonic, isTrue);

    final tooFewSamples = <DecisionStatisticsRow>[
      ..._bucketRows(score: 15, count: 19, dateCount: 5, hitCount: 10),
      ..._bucketRows(score: 25, count: 20, dateCount: 5, hitCount: 15),
    ];
    expect(
      DecisionScoreDiagnostics.analyze(tooFewSamples)
          .bullishMonotonicity
          .isMonotonic,
      isNull,
    );

    final tooFewDates = <DecisionStatisticsRow>[
      ..._bucketRows(score: 15, count: 20, dateCount: 4, hitCount: 10),
      ..._bucketRows(score: 25, count: 20, dateCount: 4, hitCount: 15),
    ];
    expect(
      DecisionScoreDiagnostics.analyze(tooFewDates)
          .bullishMonotonicity
          .isMonotonic,
      isNull,
    );
  });

  test('monotonicity reports a decline between eligible buckets', () {
    final rows = <DecisionStatisticsRow>[
      ..._bucketRows(score: 15, count: 20, dateCount: 5, hitCount: 15),
      ..._bucketRows(score: 25, count: 20, dateCount: 5, hitCount: 10),
    ];

    final result = DecisionScoreDiagnostics.analyze(rows).bullishMonotonicity;

    expect(result.eligiblePairCount, 1);
    expect(result.isMonotonic, isFalse);
    expect(result.decliningPairs, hasLength(1));
  });

  test('monotonicity ignores evaluated rows without directional labels', () {
    List<DecisionStatisticsRow> mostlyUnlabeled(double score, int offset) =>
        List.generate(
          20,
          (index) => _row(
            id: offset + index,
            signalDate: DateTime(2026, 1, 1 + index % 5),
            direction: RecommendationDirection.bullish,
            directionScore: score,
            forecastReturn: 1,
            effectiveHit: index == 0 ? true : null,
          ),
        );

    final result = DecisionScoreDiagnostics.analyze([
      ...mostlyUnlabeled(15, 1000),
      ...mostlyUnlabeled(25, 2000),
    ]).bullishMonotonicity;

    expect(result.eligiblePairCount, 0);
    expect(result.isMonotonic, isNull);
  });

  test('empty diagnostics are safe and not optimization ready', () {
    final result = DecisionScoreDiagnostics.analyze(const []);

    expect(result.scoreCorrelation.coefficient, isNull);
    expect(result.distribution.totalCount, 0);
    expect(result.readiness.isReady, isFalse);
  });

  test('readiness counts unique decisions instead of three outcome horizons',
      () {
    final rows = <DecisionStatisticsRow>[];
    const scores = <double>[15, 25, 40, 60];
    for (var bucketIndex = 0; bucketIndex < scores.length; bucketIndex++) {
      for (var decisionIndex = 0; decisionIndex < 34; decisionIndex++) {
        final id = bucketIndex * 1000 + decisionIndex + 1;
        for (final horizon in const [1, 3, 5]) {
          rows.add(_row(
            id: id,
            signalDate: DateTime(2026, 1, 1 + decisionIndex % 20),
            direction: RecommendationDirection.bullish,
            directionScore: scores[bucketIndex],
            forecastReturn: 1,
            effectiveHit: true,
            horizon: horizon,
          ));
        }
      }
    }

    expect(
      DecisionScoreDiagnostics.analyze(rows).readiness.bucketSamplesReady,
      isFalse,
    );
  });

  test('readiness can use all horizons without duplicating visible diagnostics',
      () {
    final currentHorizon = <DecisionStatisticsRow>[];
    final allHorizons = <DecisionStatisticsRow>[];
    for (var index = 0; index < 10; index++) {
      final current = _row(
        id: index + 1,
        signalDate: DateTime(2026, 1, 1 + index),
        direction: RecommendationDirection.bullish,
        directionScore: 20.0 + index,
        forecastReturn: 1.0 + index,
        effectiveHit: true,
        horizon: 1,
      );
      currentHorizon.add(current);
      allHorizons.add(current);
      allHorizons.add(_row(
        id: index + 1,
        signalDate: DateTime(2026, 1, 1 + index),
        direction: RecommendationDirection.bullish,
        directionScore: 20.0 + index,
        forecastReturn: 1.0 + index,
        effectiveHit: true,
        horizon: 3,
      ));
      allHorizons.add(_row(
        id: index + 1,
        signalDate: DateTime(2026, 1, 1 + index),
        direction: RecommendationDirection.bullish,
        directionScore: 20.0 + index,
        forecastReturn: 1.0 + index,
        effectiveHit: true,
        horizon: 5,
      ));
    }

    final result = DecisionScoreDiagnostics.analyze(
      currentHorizon,
      readinessRows: allHorizons,
    );

    expect(result.scoreCorrelation.sampleCount, 10);
    expect(result.readiness.labelCompleteness, 1);
  });
}

DecisionStatisticsRow _correlationRow(int index, {required int dateCount}) {
  final magnitude = 20.0 + index;
  return _row(
    id: index + 1,
    signalDate: DateTime(2026, 1, 1 + index % dateCount),
    direction: RecommendationDirection.bullish,
    directionScore: magnitude,
    forecastReturn: magnitude / 10,
    effectiveHit: true,
    directionComponents: {trendComponentKey: magnitude / 100},
  );
}

List<DecisionStatisticsRow> _bucketRows({
  required double score,
  required int count,
  required int dateCount,
  required int hitCount,
}) =>
    List.generate(
      count,
      (index) => _row(
        id: score.toInt() * 1000 + index,
        signalDate: DateTime(2026, 1, 1 + index % dateCount),
        direction: RecommendationDirection.bullish,
        directionScore: score,
        forecastReturn: index < hitCount ? 1 : -1,
        effectiveHit: index < hitCount,
      ),
    );

DecisionStatisticsRow _row({
  required int id,
  RecommendationDirection direction = RecommendationDirection.neutral,
  double directionScore = 0,
  double? forecastReturn,
  double? alphaReturn,
  bool? effectiveHit,
  bool? alphaHit,
  Map<String, double> directionComponents = const {},
  DateTime? signalDate,
  int horizon = 1,
  MarketRegime marketRegime = MarketRegime.range,
  DecisionOutcomeStatus status = DecisionOutcomeStatus.evaluated,
}) {
  final date = signalDate ?? DateTime(2026, 1, 1);
  return DecisionStatisticsRow(
    snapshot: DecisionSnapshotRecord(
      id: id,
      code: id.toString().padLeft(6, '0'),
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
      id: id,
      snapshotId: id,
      horizon: horizon,
      status: status,
      forecastReturn: forecastReturn,
      alphaReturn: alphaReturn,
      effectiveDirectionHit: effectiveHit,
      alphaHit: alphaHit,
    ),
  );
}
