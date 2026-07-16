import 'dart:math' as math;

import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'directional_evidence_builder.dart';

enum DecisionScoreBucket { watch, cautious, clear, strong }

extension DecisionScoreBucketLabel on DecisionScoreBucket {
  String get label => switch (this) {
        DecisionScoreBucket.watch => '观察',
        DecisionScoreBucket.cautious => '谨慎',
        DecisionScoreBucket.clear => '明确',
        DecisionScoreBucket.strong => '强烈',
      };
}

class DecisionCorrelationResult {
  final int sampleCount;
  final int signalDateCount;
  final double? coefficient;

  const DecisionCorrelationResult({
    required this.sampleCount,
    required this.signalDateCount,
    this.coefficient,
  });
}

class DecisionDirectionDistribution {
  final int bullishCount;
  final int neutralCount;
  final int bearishCount;

  const DecisionDirectionDistribution({
    required this.bullishCount,
    required this.neutralCount,
    required this.bearishCount,
  });

  int get totalCount => bullishCount + neutralCount + bearishCount;

  double get bullishRatio => _ratio(bullishCount);
  double get neutralRatio => _ratio(neutralCount);
  double get bearishRatio => _ratio(bearishCount);

  RecommendationDirection? get biasedDirection {
    if (bullishRatio > 0.7) return RecommendationDirection.bullish;
    if (neutralRatio > 0.7) return RecommendationDirection.neutral;
    if (bearishRatio > 0.7) return RecommendationDirection.bearish;
    return null;
  }

  bool get isBiased => biasedDirection != null;

  double _ratio(int count) => totalCount == 0 ? 0 : count / totalCount;
}

class DecisionScoreBucketSummary {
  final DecisionScoreBucket scoreBucket;
  final RecommendationDirection direction;
  final int sampleCount;
  final int signalDateCount;
  final int effectiveHitSampleCount;
  final int alphaHitSampleCount;
  final double? effectiveHitRate;
  final double? alphaHitRate;
  final double? meanOrientedReturn;
  final double? meanOrientedAlpha;

  const DecisionScoreBucketSummary({
    required this.scoreBucket,
    required this.direction,
    required this.sampleCount,
    required this.signalDateCount,
    required this.effectiveHitSampleCount,
    required this.alphaHitSampleCount,
    this.effectiveHitRate,
    this.alphaHitRate,
    this.meanOrientedReturn,
    this.meanOrientedAlpha,
  });
}

class DecisionDecliningBucketPair {
  final DecisionScoreBucket lower;
  final DecisionScoreBucket higher;

  const DecisionDecliningBucketPair({
    required this.lower,
    required this.higher,
  });
}

class DecisionMonotonicityResult {
  final RecommendationDirection direction;
  final int eligiblePairCount;
  final bool? isMonotonic;
  final List<DecisionDecliningBucketPair> decliningPairs;

  const DecisionMonotonicityResult({
    required this.direction,
    required this.eligiblePairCount,
    required this.isMonotonic,
    this.decliningPairs = const [],
  });
}

class DecisionOptimizationReadiness {
  final bool bucketSamplesReady;
  final bool signalDatesReady;
  final bool labelCompletenessReady;
  final bool marketRegimesReady;
  final bool timeSplitReady;
  final bool diagnosticsReady;
  final int signalDateCount;
  final double labelCompleteness;
  final Set<String> coveredMarketGroups;
  final bool isReady;

  const DecisionOptimizationReadiness({
    required this.bucketSamplesReady,
    required this.signalDatesReady,
    required this.labelCompletenessReady,
    required this.marketRegimesReady,
    required this.timeSplitReady,
    required this.diagnosticsReady,
    required this.signalDateCount,
    required this.labelCompleteness,
    required this.coveredMarketGroups,
    required this.isReady,
  });
}

class DecisionScoreDiagnosticsResult {
  final DecisionCorrelationResult scoreCorrelation;
  final Map<String, DecisionCorrelationResult> componentCorrelations;
  final DecisionDirectionDistribution distribution;
  final List<DecisionScoreBucketSummary> buckets;
  final DecisionMonotonicityResult bullishMonotonicity;
  final DecisionMonotonicityResult bearishMonotonicity;
  final DecisionOptimizationReadiness readiness;

  const DecisionScoreDiagnosticsResult({
    required this.scoreCorrelation,
    required this.componentCorrelations,
    required this.distribution,
    required this.buckets,
    required this.bullishMonotonicity,
    required this.bearishMonotonicity,
    required this.readiness,
  });

  DecisionScoreBucketSummary bucket(
    RecommendationDirection direction,
    DecisionScoreBucket scoreBucket,
  ) =>
      buckets.firstWhere(
        (item) =>
            item.direction == direction && item.scoreBucket == scoreBucket,
      );
}

class DecisionScoreDiagnostics {
  static const List<String> componentKeys = <String>[
    trendComponentKey,
    reversalMomentumComponentKey,
    volumeFlowComponentKey,
    relativeStrengthComponentKey,
    nextSessionComponentKey,
  ];

  static DecisionScoreBucket? bucketFor(double directionScore) {
    if (!directionScore.isFinite) return null;
    final strength = directionScore.abs();
    if (strength < 12 || strength > 100) return null;
    if (strength < 20) return DecisionScoreBucket.watch;
    if (strength < 35) return DecisionScoreBucket.cautious;
    if (strength < 55) return DecisionScoreBucket.clear;
    return DecisionScoreBucket.strong;
  }

  static DecisionScoreDiagnosticsResult analyze(
    List<DecisionStatisticsRow> rows, {
    List<DecisionStatisticsRow>? readinessRows,
  }) {
    final directionalMature = rows
        .where((row) =>
            row.outcome.status == DecisionOutcomeStatus.evaluated &&
            row.snapshot.direction != RecommendationDirection.neutral &&
            row.outcome.forecastReturn != null)
        .toList(growable: false);

    final scoreCorrelation = _correlation(
      directionalMature,
      (row) => row.snapshot.directionScore,
    );
    final componentCorrelations = <String, DecisionCorrelationResult>{
      for (final key in componentKeys)
        key: _correlation(
          directionalMature.where((row) {
            final value = row.snapshot.directionComponents[key];
            return value != null && value.isFinite;
          }).toList(growable: false),
          (row) => row.snapshot.directionComponents[key]!,
        ),
    };
    final distribution = _distribution(rows);
    final buckets = <DecisionScoreBucketSummary>[
      for (final direction in const [
        RecommendationDirection.bullish,
        RecommendationDirection.bearish,
      ])
        for (final scoreBucket in DecisionScoreBucket.values)
          _bucketSummary(rows, direction, scoreBucket),
    ];
    final bullishMonotonicity =
        _monotonicity(buckets, RecommendationDirection.bullish);
    final bearishMonotonicity =
        _monotonicity(buckets, RecommendationDirection.bearish);
    final readiness = _readiness(
      readinessRows ?? rows,
      scoreCorrelation,
      componentCorrelations,
      bullishMonotonicity,
      bearishMonotonicity,
    );

    return DecisionScoreDiagnosticsResult(
      scoreCorrelation: scoreCorrelation,
      componentCorrelations: componentCorrelations,
      distribution: distribution,
      buckets: buckets,
      bullishMonotonicity: bullishMonotonicity,
      bearishMonotonicity: bearishMonotonicity,
      readiness: readiness,
    );
  }

  static double? spearman(List<double> x, List<double> y) {
    if (x.length != y.length || x.length < 2) return null;
    if (x.any((value) => !value.isFinite) ||
        y.any((value) => !value.isFinite)) {
      return null;
    }
    final xRanks = _averageRanks(x);
    final yRanks = _averageRanks(y);
    final xMean = xRanks.reduce((a, b) => a + b) / xRanks.length;
    final yMean = yRanks.reduce((a, b) => a + b) / yRanks.length;
    var numerator = 0.0;
    var xSquared = 0.0;
    var ySquared = 0.0;
    for (var index = 0; index < xRanks.length; index++) {
      final xDelta = xRanks[index] - xMean;
      final yDelta = yRanks[index] - yMean;
      numerator += xDelta * yDelta;
      xSquared += xDelta * xDelta;
      ySquared += yDelta * yDelta;
    }
    final denominator = math.sqrt(xSquared * ySquared);
    if (denominator == 0) return null;
    return (numerator / denominator).clamp(-1.0, 1.0).toDouble();
  }

  static DecisionCorrelationResult _correlation(
    List<DecisionStatisticsRow> rows,
    double Function(DecisionStatisticsRow row) selectX,
  ) {
    final usable = rows.where((row) {
      final x = selectX(row);
      final y = row.outcome.forecastReturn;
      return x.isFinite && y != null && y.isFinite;
    }).toList(growable: false);
    final signalDateCount = usable
        .map((row) => _dateKey(row.snapshot.signalTradeDate))
        .toSet()
        .length;
    final eligible = usable.length >= 30 && signalDateCount >= 10;
    return DecisionCorrelationResult(
      sampleCount: usable.length,
      signalDateCount: signalDateCount,
      coefficient: eligible
          ? spearman(
              usable.map(selectX).toList(growable: false),
              usable
                  .map((row) => row.outcome.forecastReturn!)
                  .toList(growable: false),
            )
          : null,
    );
  }

  static DecisionDirectionDistribution _distribution(
    List<DecisionStatisticsRow> rows,
  ) {
    final snapshots = <String, DecisionSnapshotRecord>{};
    for (final row in rows) {
      snapshots.putIfAbsent(_snapshotKey(row.snapshot), () => row.snapshot);
    }
    var bullish = 0;
    var neutral = 0;
    var bearish = 0;
    for (final snapshot in snapshots.values) {
      switch (snapshot.direction) {
        case RecommendationDirection.bullish:
          bullish++;
        case RecommendationDirection.neutral:
          neutral++;
        case RecommendationDirection.bearish:
          bearish++;
      }
    }
    return DecisionDirectionDistribution(
      bullishCount: bullish,
      neutralCount: neutral,
      bearishCount: bearish,
    );
  }

  static DecisionScoreBucketSummary _bucketSummary(
    List<DecisionStatisticsRow> rows,
    RecommendationDirection direction,
    DecisionScoreBucket scoreBucket,
  ) {
    final bucketRows = rows
        .where((row) =>
            row.outcome.status == DecisionOutcomeStatus.evaluated &&
            row.snapshot.direction == direction &&
            bucketFor(row.snapshot.directionScore) == scoreBucket)
        .toList(growable: false);
    final effectiveHits = bucketRows
        .map((row) => row.outcome.effectiveDirectionHit)
        .whereType<bool>()
        .toList(growable: false);
    final alphaHits = bucketRows
        .map((row) => row.outcome.alphaHit)
        .whereType<bool>()
        .toList(growable: false);
    final orientation =
        direction == RecommendationDirection.bearish ? -1.0 : 1.0;
    final orientedReturns = bucketRows
        .map((row) => row.outcome.forecastReturn)
        .whereType<double>()
        .map((value) => value * orientation)
        .toList(growable: false);
    final orientedAlphas = bucketRows
        .map((row) => row.outcome.alphaReturn)
        .whereType<double>()
        .map((value) => value * orientation)
        .toList(growable: false);
    return DecisionScoreBucketSummary(
      scoreBucket: scoreBucket,
      direction: direction,
      sampleCount: bucketRows.length,
      signalDateCount: bucketRows
          .map((row) => _dateKey(row.snapshot.signalTradeDate))
          .toSet()
          .length,
      effectiveHitSampleCount: effectiveHits.length,
      alphaHitSampleCount: alphaHits.length,
      effectiveHitRate: _hitRate(effectiveHits),
      alphaHitRate: _hitRate(alphaHits),
      meanOrientedReturn: _mean(orientedReturns),
      meanOrientedAlpha: _mean(orientedAlphas),
    );
  }

  static DecisionMonotonicityResult _monotonicity(
    List<DecisionScoreBucketSummary> buckets,
    RecommendationDirection direction,
  ) {
    final directional = DecisionScoreBucket.values
        .map((scoreBucket) => buckets.firstWhere(
              (item) =>
                  item.direction == direction &&
                  item.scoreBucket == scoreBucket,
            ))
        .toList(growable: false);
    var eligiblePairCount = 0;
    final declining = <DecisionDecliningBucketPair>[];
    for (var index = 0; index < directional.length - 1; index++) {
      final lower = directional[index];
      final higher = directional[index + 1];
      final eligible = lower.sampleCount >= 20 &&
          higher.sampleCount >= 20 &&
          lower.signalDateCount >= 5 &&
          higher.signalDateCount >= 5 &&
          lower.effectiveHitRate != null &&
          higher.effectiveHitRate != null;
      if (!eligible) continue;
      eligiblePairCount++;
      if (higher.effectiveHitRate! + 1e-12 < lower.effectiveHitRate!) {
        declining.add(DecisionDecliningBucketPair(
          lower: lower.scoreBucket,
          higher: higher.scoreBucket,
        ));
      }
    }
    return DecisionMonotonicityResult(
      direction: direction,
      eligiblePairCount: eligiblePairCount,
      isMonotonic: eligiblePairCount == 0 ? null : declining.isEmpty,
      decliningPairs: List.unmodifiable(declining),
    );
  }

  static DecisionOptimizationReadiness _readiness(
    List<DecisionStatisticsRow> rows,
    DecisionCorrelationResult scoreCorrelation,
    Map<String, DecisionCorrelationResult> componentCorrelations,
    DecisionMonotonicityResult bullishMonotonicity,
    DecisionMonotonicityResult bearishMonotonicity,
  ) {
    final primaryMatureSnapshots = <String, DecisionSnapshotRecord>{};
    for (final row in rows) {
      final key = _snapshotKey(row.snapshot);
      if (row.outcome.horizon == 1 &&
          row.outcome.status == DecisionOutcomeStatus.evaluated &&
          row.snapshot.direction != RecommendationDirection.neutral &&
          bucketFor(row.snapshot.directionScore) != null) {
        primaryMatureSnapshots.putIfAbsent(key, () => row.snapshot);
      }
    }
    final signalDateCount = primaryMatureSnapshots.values
        .map((snapshot) => _dateKey(snapshot.signalTradeDate))
        .toSet()
        .length;
    final bucketSamplesReady = DecisionScoreBucket.values.every((scoreBucket) {
      final count = primaryMatureSnapshots.values
          .where(
              (snapshot) => bucketFor(snapshot.directionScore) == scoreBucket)
          .length;
      return count >= 100;
    });
    final labeledOutcomes = <String>{};
    for (final row in rows) {
      final snapshotKey = _snapshotKey(row.snapshot);
      if (primaryMatureSnapshots.containsKey(snapshotKey) &&
          row.outcome.status == DecisionOutcomeStatus.evaluated) {
        labeledOutcomes.add(
          '$snapshotKey|${row.outcome.horizon}',
        );
      }
    }
    final expectedLabels = primaryMatureSnapshots.length * 3;
    final labelCompleteness = expectedLabels == 0
        ? 0.0
        : (labeledOutcomes.length / expectedLabels).clamp(0.0, 1.0);
    final coveredMarketGroups = primaryMatureSnapshots.values
        .map((snapshot) => _marketGroup(snapshot.marketRegime))
        .whereType<String>()
        .toSet();
    final signalDatesReady = signalDateCount >= 20;
    final labelCompletenessReady = labelCompleteness >= 0.95;
    final marketRegimesReady = coveredMarketGroups.containsAll(
      const <String>{'bull', 'rebound', 'range', 'bear'},
    );
    final timeSplitReady = signalDateCount >= 20;
    final diagnosticsReady = scoreCorrelation.coefficient != null &&
        componentKeys.every(
          (key) => componentCorrelations[key]?.coefficient != null,
        ) &&
        bullishMonotonicity.isMonotonic != null &&
        bearishMonotonicity.isMonotonic != null;
    final isReady = bucketSamplesReady &&
        signalDatesReady &&
        labelCompletenessReady &&
        marketRegimesReady &&
        timeSplitReady &&
        diagnosticsReady;
    return DecisionOptimizationReadiness(
      bucketSamplesReady: bucketSamplesReady,
      signalDatesReady: signalDatesReady,
      labelCompletenessReady: labelCompletenessReady,
      marketRegimesReady: marketRegimesReady,
      timeSplitReady: timeSplitReady,
      diagnosticsReady: diagnosticsReady,
      signalDateCount: signalDateCount,
      labelCompleteness: labelCompleteness,
      coveredMarketGroups: Set.unmodifiable(coveredMarketGroups),
      isReady: isReady,
    );
  }

  static List<double> _averageRanks(List<double> values) {
    final indexes = List<int>.generate(values.length, (index) => index)
      ..sort((a, b) => values[a].compareTo(values[b]));
    final ranks = List<double>.filled(values.length, 0);
    var start = 0;
    while (start < indexes.length) {
      var end = start + 1;
      while (end < indexes.length &&
          values[indexes[end]] == values[indexes[start]]) {
        end++;
      }
      final averageRank = ((start + 1) + end) / 2;
      for (var position = start; position < end; position++) {
        ranks[indexes[position]] = averageRank;
      }
      start = end;
    }
    return ranks;
  }

  static double? _hitRate(List<bool> values) => values.isEmpty
      ? null
      : values.where((value) => value).length / values.length;

  static double? _mean(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

  static String _snapshotKey(DecisionSnapshotRecord snapshot) => snapshot.id !=
          null
      ? 'id:${snapshot.id}'
      : '${snapshot.source}|${snapshot.code}|${snapshot.signalTime.microsecondsSinceEpoch}|${snapshot.modelVersion}';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _marketGroup(MarketRegime regime) => switch (regime) {
        MarketRegime.bullishTrend => 'bull',
        MarketRegime.rebound => 'rebound',
        MarketRegime.range || MarketRegime.highVolatility => 'range',
        MarketRegime.bearishTrend || MarketRegime.pullback => 'bear',
        MarketRegime.unknown => null,
      };
}
