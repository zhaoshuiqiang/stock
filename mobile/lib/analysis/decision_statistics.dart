import '../models/stock_models.dart';
import 'calibration_metrics.dart';

class DecisionStatisticsFilter {
  final int? horizon;
  const DecisionStatisticsFilter({this.horizon});
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
  final double? coverage;
  final double? rawHitRate;
  final double? effectiveHitRate;
  final double? alphaHitRate;
  final ConfidenceInterval? rawHitWilson;
  final double? meanReturn;
  final double? medianReturn;
  final double? meanAlpha;
  final double? medianAlpha;
  final double? meanMfe;
  final double? meanMae;
  final DecisionCalibrationQuality calibration;

  const DecisionStatisticsSummary({
    required this.evaluatedCount,
    required this.pendingCount,
    required this.maturedPendingCount,
    required this.invalidCount,
    this.coverage,
    this.rawHitRate,
    this.effectiveHitRate,
    this.alphaHitRate,
    this.rawHitWilson,
    this.meanReturn,
    this.medianReturn,
    this.meanAlpha,
    this.medianAlpha,
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
    final invalid = rows
        .where((row) => row.outcome.status == DecisionOutcomeStatus.invalid)
        .length;
    final pending = rows
        .where((row) => row.outcome.status == DecisionOutcomeStatus.pending)
        .toList(growable: false);
    final maturedPending = pending.where((row) {
      final due = row.outcome.dueTradeDate;
      return due != null && !due.isAfter(current);
    }).length;
    final coverageDenominator = evaluated.length + invalid + maturedPending;
    final rawHits = evaluated
        .where((row) => row.outcome.rawDirectionHit != null)
        .map((row) => row.outcome.rawDirectionHit!)
        .toList();
    final effectiveHits = evaluated
        .where((row) => row.outcome.effectiveDirectionHit != null)
        .map((row) => row.outcome.effectiveDirectionHit!)
        .toList();
    final alphaHits = evaluated
        .where((row) => row.outcome.alphaHit != null)
        .map((row) => row.outcome.alphaHit!)
        .toList();
    final returns = _values(evaluated, (row) => row.outcome.forecastReturn);
    final alphas = _values(evaluated, (row) => row.outcome.alphaReturn);
    final mfes = _values(evaluated, (row) => row.outcome.mfe);
    final maes = _values(evaluated, (row) => row.outcome.mae);
    final probabilityRows = evaluated
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
    return DecisionStatisticsSummary(
      evaluatedCount: evaluated.length,
      pendingCount: pending.length,
      maturedPendingCount: maturedPending,
      invalidCount: invalid,
      coverage: coverageDenominator == 0
          ? null
          : evaluated.length / coverageDenominator,
      rawHitRate: _hitRate(rawHits),
      effectiveHitRate: _hitRate(effectiveHits),
      alphaHitRate: _hitRate(alphaHits),
      rawHitWilson: rawHits.isEmpty
          ? null
          : wilsonInterval(hits: rawHitCount, sampleCount: rawHits.length),
      meanReturn: _mean(returns),
      medianReturn: _median(returns),
      meanAlpha: _mean(alphas),
      medianAlpha: _median(alphas),
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
}
