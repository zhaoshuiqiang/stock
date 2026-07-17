import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import '../storage/database_service.dart';
import 'decision_calibrator.dart';

typedef DecisionCalibrationRowLoader = Future<List<DecisionCalibrationRow>>
    Function(String modelVersion, DateTime asOfTradeDate);

class DecisionCalibrationService {
  final DecisionCalibrationRowLoader _rowLoader;

  // v3.39: 缓存校准行数据，批量场景下420只股票共享同一次DB查询结果
  static final Map<String, _CacheEntry<List<DecisionCalibrationRow>>> _rowCache = {};

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

    final cacheKey = '${decision.modelVersion}_${asOfTradeDate.toIso8601String().substring(0, 10)}';
    List<DecisionCalibrationRow> rows;
    final cached = _rowCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      rows = cached.data;
    } else {
      rows = await _rowLoader(decision.modelVersion, asOfTradeDate);
      _rowCache[cacheKey] = _CacheEntry(rows);
      // 防止缓存无限增长
      if (_rowCache.length > 10) {
        _rowCache.removeWhere((_, v) => v.isExpired);
      }
    }

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

class _CacheEntry<T> {
  final T data;
  final DateTime _createdAt;
  static const Duration _ttl = Duration(minutes: 5);

  _CacheEntry(this.data) : _createdAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(_createdAt) > _ttl;
}
