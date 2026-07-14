import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import '../storage/database_service.dart';
import 'decision_calibrator.dart';

typedef DecisionCalibrationRowLoader = Future<List<DecisionCalibrationRow>>
    Function(String modelVersion, DateTime asOfTradeDate);

class DecisionCalibrationService {
  final DecisionCalibrationRowLoader _rowLoader;

  DecisionCalibrationService({
    DecisionCalibrationRowLoader? rowLoader,
    DatabaseService? storage,
  }) : _rowLoader = rowLoader ??
            ((modelVersion, asOfTradeDate) =>
                (storage ?? DatabaseService()).getDecisionCalibrationRows(
                  modelVersion: modelVersion,
                  asOfTradeDate: asOfTradeDate,
                ));

  Future<AnalysisResult> enrich(
    AnalysisResult analysis, {
    required DateTime asOfTradeDate,
  }) async {
    final decision = analysis.shortTermDecision;
    if (decision == null) return analysis;
    final rows = await _rowLoader(decision.modelVersion, asOfTradeDate);
    final model = DecisionCalibrator.buildModel(
      rows,
      asOfTradeDate: asOfTradeDate,
    );
    final estimates = <int, CalibrationEstimate>{};
    for (final horizon in const [1, 3, 5]) {
      final estimate = model.estimate(
        modelVersion: decision.modelVersion,
        horizon: horizon,
        direction: decision.direction,
        directionScore: decision.directionScore,
        marketRegime: decision.marketRegime,
      );
      if (estimate != null) estimates[horizon] = estimate;
    }
    return analysis.copyWith(
      shortTermDecision: decision.copyWith(
        calibrationByHorizon: estimates,
      ),
    );
  }
}
