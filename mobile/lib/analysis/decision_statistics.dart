import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import 'calibration_metrics.dart';

class DecisionStatisticsFilter {
  final int? horizon;
  final RecommendationDirection? direction;
  final MarketRegime? marketRegime;
  final String? modelVersion;
  final String? source;
  final List<String>? sources;
  final DecisionSignalPhase? signalPhase;
  final DateTime? startTradeDate;
  final DateTime? endTradeDate;
  final bool includeRetrospective;

  const DecisionStatisticsFilter({
    this.horizon,
    this.direction,
    this.marketRegime,
    this.modelVersion,
    this.source,
    this.sources,
    this.signalPhase,
    this.startTradeDate,
    this.endTradeDate,
    this.includeRetrospective = false,
  });
}

class DecisionCalibrationQuality {
  final int sampleCount;
  final int signalDateCount;
  final double? brier;
  final double? ece;

  const DecisionCalibrationQuality({
    required this.sampleCount,
    required this.signalDateCount,
    this.brier,
    this.ece,
  });
}

class DecisionBucketStatistics {
  final String label;
  final int sampleCount;
  final double? effectiveHitRate;

  const DecisionBucketStatistics({
    required this.label,
    required this.sampleCount,
    this.effectiveHitRate,
  });
}

class DecisionStatisticsSummary {
  final int evaluatedCount;
  final int pendingCount;
  final int maturedPendingCount;
  final int invalidCount;
  final int rawHitSampleCount;
  final int effectiveHitSampleCount;
  final int alphaHitSampleCount;
  final int bullishSampleCount;
  final int bearishSampleCount;
  final int neutralSampleCount;
  final int orientedSampleCount;
  final int orientedAlphaSampleCount;
  final double? coverage;
  final double? rawHitRate;
  final double? effectiveHitRate;
  final double? alphaHitRate;
  final double? bullishEffectiveHitRate;
  final double? bearishEffectiveHitRate;
  final double? balancedEffectiveHitRate;
  final double? neutralStabilityRate;
  final ConfidenceInterval? rawHitWilson;
  final double? meanReturn;
  final double? medianReturn;
  final double? meanAlpha;
  final double? medianAlpha;
  final double? meanOrientedReturn;
  final double? medianOrientedReturn;
  final double? meanOrientedAlpha;
  final double? medianOrientedAlpha;
  final double? meanMfe;
  final double? meanMae;
  final DecisionCalibrationQuality calibration;

  const DecisionStatisticsSummary({
    required this.evaluatedCount,
    required this.pendingCount,
    required this.maturedPendingCount,
    required this.invalidCount,
    this.rawHitSampleCount = 0,
    this.effectiveHitSampleCount = 0,
    this.alphaHitSampleCount = 0,
    this.bullishSampleCount = 0,
    this.bearishSampleCount = 0,
    this.neutralSampleCount = 0,
    this.orientedSampleCount = 0,
    this.orientedAlphaSampleCount = 0,
    this.coverage,
    this.rawHitRate,
    this.effectiveHitRate,
    this.alphaHitRate,
    this.bullishEffectiveHitRate,
    this.bearishEffectiveHitRate,
    this.balancedEffectiveHitRate,
    this.neutralStabilityRate,
    this.rawHitWilson,
    this.meanReturn,
    this.medianReturn,
    this.meanAlpha,
    this.medianAlpha,
    this.meanOrientedReturn,
    this.medianOrientedReturn,
    this.meanOrientedAlpha,
    this.medianOrientedAlpha,
    this.meanMfe,
    this.meanMae,
    required this.calibration,
  });
}

class DecisionStatistics {
  static DecisionStatisticsSummary summarize(
    List<DecisionStatisticsRow> rows, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final evaluated = rows
        .where((row) => row.outcome.status == DecisionOutcomeStatus.evaluated)
        .toList(growable: false);
    final directionalEvaluated = evaluated
        .where(
            (row) => row.snapshot.direction != RecommendationDirection.neutral)
        .toList(growable: false);
    final invalid = rows
        .where((row) => row.outcome.status == DecisionOutcomeStatus.invalid)
        .length;
    final pending = rows
        .where((row) => row.outcome.status == DecisionOutcomeStatus.pending)
        .toList(growable: false);
    final maturedPending = pending.where((row) {
      final due = row.outcome.dueTradeDate;
      return due != null && _isMatured(due, current);
    }).length;
    final coverageDenominator = evaluated.length + invalid + maturedPending;
    final rawHits = directionalEvaluated
        .where((row) => row.outcome.rawDirectionHit != null)
        .map((row) => row.outcome.rawDirectionHit!)
        .toList();
    final effectiveHits = directionalEvaluated
        .where((row) => row.outcome.effectiveDirectionHit != null)
        .map((row) => row.outcome.effectiveDirectionHit!)
        .toList();
    final alphaHits = directionalEvaluated
        .where((row) => row.outcome.alphaHit != null)
        .map((row) => row.outcome.alphaHit!)
        .toList();
    final bullishHits = evaluated
        .where((row) =>
            row.snapshot.direction == RecommendationDirection.bullish &&
            row.outcome.effectiveDirectionHit != null)
        .map((row) => row.outcome.effectiveDirectionHit!)
        .toList(growable: false);
    final bearishHits = evaluated
        .where((row) =>
            row.snapshot.direction == RecommendationDirection.bearish &&
            row.outcome.effectiveDirectionHit != null)
        .map((row) => row.outcome.effectiveDirectionHit!)
        .toList(growable: false);
    final neutralStability = evaluated
        .where((row) =>
            row.snapshot.direction == RecommendationDirection.neutral &&
            row.outcome.alphaReturn != null)
        .map((row) => row.outcome.alphaReturn!.abs() <= 0.5)
        .toList(growable: false);
    final returns = _values(evaluated, (row) => row.outcome.forecastReturn);
    final alphas = _values(evaluated, (row) => row.outcome.alphaReturn);
    final orientedReturns = _orientedValues(
      evaluated,
      (row) => row.outcome.forecastReturn,
    );
    final orientedAlphas = _orientedValues(
      evaluated,
      (row) => row.outcome.alphaReturn,
    );
    final mfes = _values(directionalEvaluated, (row) => row.outcome.mfe);
    final maes = _values(directionalEvaluated, (row) => row.outcome.mae);
    final probabilityRows = directionalEvaluated
        .where((row) =>
            row.outcome.predictedProbability != null &&
            row.outcome.effectiveDirectionHit != null)
        .toList(growable: false);
    final signalDates = probabilityRows
        .map((row) =>
            '${row.snapshot.signalTradeDate.year}-${row.snapshot.signalTradeDate.month}-${row.snapshot.signalTradeDate.day}')
        .toSet()
        .length;
    final probabilitySamples = probabilityRows
        .map((row) => ProbabilityOutcome(
              probability: row.outcome.predictedProbability!,
              outcome: row.outcome.effectiveDirectionHit!,
            ))
        .toList(growable: false);
    final calibrationEligible =
        probabilitySamples.length >= 30 && signalDates >= 10;
    final rawHitCount = rawHits.where((hit) => hit).length;
    final bullishHitRate = _hitRate(bullishHits);
    final bearishHitRate = _hitRate(bearishHits);
    return DecisionStatisticsSummary(
      evaluatedCount: evaluated.length,
      pendingCount: pending.length,
      maturedPendingCount: maturedPending,
      invalidCount: invalid,
      rawHitSampleCount: rawHits.length,
      effectiveHitSampleCount: effectiveHits.length,
      alphaHitSampleCount: alphaHits.length,
      bullishSampleCount: bullishHits.length,
      bearishSampleCount: bearishHits.length,
      neutralSampleCount: neutralStability.length,
      orientedSampleCount: orientedReturns.length,
      orientedAlphaSampleCount: orientedAlphas.length,
      coverage: coverageDenominator == 0
          ? null
          : evaluated.length / coverageDenominator,
      rawHitRate: _hitRate(rawHits),
      effectiveHitRate: _hitRate(effectiveHits),
      alphaHitRate: _hitRate(alphaHits),
      bullishEffectiveHitRate: bullishHitRate,
      bearishEffectiveHitRate: bearishHitRate,
      balancedEffectiveHitRate: bullishHitRate == null || bearishHitRate == null
          ? null
          : (bullishHitRate + bearishHitRate) / 2,
      neutralStabilityRate: _hitRate(neutralStability),
      rawHitWilson: rawHits.isEmpty
          ? null
          : wilsonInterval(hits: rawHitCount, sampleCount: rawHits.length),
      meanReturn: _mean(returns),
      medianReturn: _median(returns),
      meanAlpha: _mean(alphas),
      medianAlpha: _median(alphas),
      meanOrientedReturn: _mean(orientedReturns),
      medianOrientedReturn: _median(orientedReturns),
      meanOrientedAlpha: _mean(orientedAlphas),
      medianOrientedAlpha: _median(orientedAlphas),
      meanMfe: _mean(mfes),
      meanMae: _mean(maes),
      calibration: DecisionCalibrationQuality(
        sampleCount: probabilitySamples.length,
        signalDateCount: signalDates,
        brier: calibrationEligible ? brierScore(probabilitySamples) : null,
        ece: calibrationEligible
            ? expectedCalibrationError(probabilitySamples)
            : null,
      ),
    );
  }

  static List<double> _values(
    List<DecisionStatisticsRow> rows,
    double? Function(DecisionStatisticsRow row) select,
  ) =>
      rows.map(select).whereType<double>().toList(growable: false);

  static List<double> _orientedValues(
    List<DecisionStatisticsRow> rows,
    double? Function(DecisionStatisticsRow row) select,
  ) =>
      rows
          .map((row) {
            final value = select(row);
            if (value == null) return null;
            switch (row.snapshot.direction) {
              case RecommendationDirection.bullish:
                return value;
              case RecommendationDirection.bearish:
                return -value;
              case RecommendationDirection.neutral:
                return null;
            }
          })
          .whereType<double>()
          .toList(growable: false);

  static double? _hitRate(List<bool> values) => values.isEmpty
      ? null
      : values.where((value) => value).length / values.length;
  static double? _mean(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static bool _isMatured(DateTime due, DateTime current) {
    final dueDate = DateTime(due.year, due.month, due.day);
    final currentDate = DateTime(current.year, current.month, current.day);
    if (dueDate.isBefore(currentDate)) return true;
    if (dueDate.isAfter(currentDate)) return false;
    return current.hour * 60 + current.minute >= 15 * 60;
  }
}
