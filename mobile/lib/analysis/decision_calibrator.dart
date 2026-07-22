import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'calibration_metrics.dart';
import 'scoring_config.dart';

class DecisionCalibrator {
  static DecisionCalibrationModel buildModel(
    List<DecisionCalibrationRow> rows, {
    required DateTime asOfTradeDate,
  }) {
    final knowable = rows.where((row) {
      if (row.status == DecisionOutcomeStatus.pending) return true;
      final target = row.targetTradeDate;
      return target != null && target.isBefore(_date(asOfTradeDate));
    }).toList(growable: false);
    return DecisionCalibrationModel._(knowable);
  }

  static int? strengthBand(double directionScore) {
    final strength = directionScore.abs();
    if (strength < 12 || strength > 100) return null;
    if (strength < 20) return 0;
    if (strength < 35) return 1;
    if (strength < 55) return 2;
    return 3;
  }

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class DecisionCalibrationModel {
  final List<DecisionCalibrationRow> _rows;

  const DecisionCalibrationModel._(this._rows);

  CalibrationEstimate? estimate({
    required String modelVersion,
    required int horizon,
    required RecommendationDirection direction,
    required double directionScore,
    required MarketRegime marketRegime,
  }) {
    if (direction == RecommendationDirection.neutral) return null;
    final band = DecisionCalibrator.strengthBand(directionScore);
    if (band == null) return null;
    final global = _rows
        .where((row) =>
            row.modelVersion == modelVersion &&
            row.horizon == horizon &&
            row.direction == direction)
        .toList(growable: false);

    // Strict tier: (marketRegime x strengthBand) bucket with the full
    // statistical gates. Byte-identical to the pre-v4.14 behavior; always
    // tried first, and the only tier when cold-start is disabled.
    final strict = _estimateFor(
      global.where((row) =>
          row.marketRegime == marketRegime &&
          DecisionCalibrator.strengthBand(row.directionScore) == band),
      global,
      horizon,
      minValid: 100,
      minDates: 20,
      minRate: 0.95,
      isColdStart: false,
    );
    if (strict != null) return strict;

    // v4.14 cold-start: only when explicitly enabled, progressively widen the
    // bucket (drop regime, then drop band) with lower floors so a usable — but
    // clearly-labeled small-sample — estimate appears before the strict bucket
    // has accumulated. Off by default => returns null exactly like before.
    if (!ScoringConfig.useCalibrationColdStart) return null;

    final bandTier = _estimateFor(
      global.where(
          (row) => DecisionCalibrator.strengthBand(row.directionScore) == band),
      global,
      horizon,
      minValid: 40,
      minDates: 10,
      minRate: 0.80,
      isColdStart: true,
    );
    if (bandTier != null) return bandTier;

    return _estimateFor(
      global,
      global,
      horizon,
      minValid: 20,
      minDates: 8,
      minRate: 0.70,
      isColdStart: true,
    );
  }

  /// Computes a Beta-Binomial posterior + Wilson interval for [bucket] when it
  /// clears the (minValid, minDates, minRate) gates, using [global] only for
  /// the base-rate prior. Returns null when the gates are not met.
  CalibrationEstimate? _estimateFor(
    Iterable<DecisionCalibrationRow> bucket,
    List<DecisionCalibrationRow> global,
    int horizon, {
    required int minValid,
    required int minDates,
    required double minRate,
    required bool isColdStart,
  }) {
    final total = bucket.length;
    if (total == 0) return null;
    final valid = bucket
        .where((row) =>
            row.status == DecisionOutcomeStatus.evaluated &&
            row.effectiveDirectionHit != null)
        .toList(growable: false);
    if (valid.length < minValid) return null;
    final distinctDates = valid
        .map((row) =>
            '${row.signalTradeDate.year}-${row.signalTradeDate.month}-${row.signalTradeDate.day}')
        .toSet()
        .length;
    if (distinctDates < minDates || valid.length / total < minRate) return null;
    final globalValid = global.where((row) =>
        row.status == DecisionOutcomeStatus.evaluated &&
        row.effectiveDirectionHit != null);
    final globalCount = globalValid.length;
    if (globalCount == 0) return null;
    final globalHits =
        globalValid.where((row) => row.effectiveDirectionHit!).length;
    final hits = valid.where((row) => row.effectiveDirectionHit!).length;
    final interval = wilsonInterval(hits: hits, sampleCount: valid.length);
    return CalibrationEstimate(
      horizon: horizon,
      probability: betaBinomialPosterior(
        hits: hits,
        sampleCount: valid.length,
        globalBaseRate: globalHits / globalCount,
      ),
      sampleCount: valid.length,
      wilsonLower: interval.lower,
      wilsonUpper: interval.upper,
      isColdStart: isColdStart,
    );
  }
}
