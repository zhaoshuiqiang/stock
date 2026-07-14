import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'calibration_metrics.dart';

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
    final global = _rows.where((row) =>
        row.modelVersion == modelVersion &&
        row.horizon == horizon &&
        row.direction == direction);
    final bucket = global.where((row) =>
        row.marketRegime == marketRegime &&
        DecisionCalibrator.strengthBand(row.directionScore) == band);
    final total = bucket.length;
    if (total == 0) return null;
    final valid = bucket
        .where((row) =>
            row.status == DecisionOutcomeStatus.evaluated &&
            row.effectiveDirectionHit != null)
        .toList(growable: false);
    if (valid.length < 100) return null;
    final distinctDates = valid
        .map((row) =>
            '${row.signalTradeDate.year}-${row.signalTradeDate.month}-${row.signalTradeDate.day}')
        .toSet()
        .length;
    if (distinctDates < 20 || valid.length / total < 0.95) return null;
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
    );
  }
}
