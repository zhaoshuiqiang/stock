import '../models/stock_models.dart';
import '../models/short_term_decision.dart';

/// Typed filter for [DatabaseService.getDecisionStatisticsRows].
///
/// The former statistics-summary machinery (`DecisionStatistics.summarize` and
/// its `DecisionStatisticsSummary` / `DecisionCalibrationQuality` /
/// `DecisionBucketStatistics` value types) backed the removed recommendation
/// stats screen and has been deleted. This filter stays because the live
/// per-stock calibration path (getDecisionStatisticsRows ->
/// getDecisionCalibrationRows -> DecisionCalibrationService) still depends on it.
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
