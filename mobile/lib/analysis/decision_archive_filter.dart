import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

enum DecisionArchiveSourceGroup { manual, scan, all }

const DecisionArchiveViewFilter kDefaultDecisionArchiveFilter =
    DecisionArchiveViewFilter.premarketV3();

class DecisionArchiveViewFilter {
  final int horizon;
  final DecisionArchiveSourceGroup sourceGroup;
  final DecisionSignalPhase? signalPhase;
  final RecommendationDirection? direction;
  final MarketRegime? marketRegime;
  final String? modelVersion;
  final bool includeRetrospective;
  final DateTime? startTradeDate;
  final DateTime? endTradeDate;

  const DecisionArchiveViewFilter({
    this.horizon = 1,
    this.sourceGroup = DecisionArchiveSourceGroup.manual,
    this.signalPhase,
    this.direction,
    this.marketRegime,
    this.modelVersion,
    this.includeRetrospective = false,
    this.startTradeDate,
    this.endTradeDate,
  });

  const DecisionArchiveViewFilter.premarketV3()
      : horizon = 1,
        sourceGroup = DecisionArchiveSourceGroup.manual,
        signalPhase = DecisionSignalPhase.preMarket,
        direction = null,
        marketRegime = null,
        modelVersion = 'short-term-v3',
        includeRetrospective = false,
        startTradeDate = null,
        endTradeDate = null;

  List<DecisionStatisticsRow> apply(
    List<DecisionStatisticsRow> rows, {
    bool includeAllHorizons = false,
  }) =>
      rows.where((row) {
        final snapshot = row.snapshot;
        if (!includeAllHorizons && row.outcome.horizon != horizon) return false;
        if (!_matchesSource(snapshot.source)) return false;
        if (!includeRetrospective &&
            (snapshot.isRetrospective ||
                snapshot.source == 'archive_backfill')) {
          return false;
        }
        if (signalPhase != null && snapshot.signalPhase != signalPhase) {
          return false;
        }
        if (direction != null && snapshot.direction != direction) return false;
        if (marketRegime != null && snapshot.marketRegime != marketRegime) {
          return false;
        }
        if (modelVersion != null && snapshot.modelVersion != modelVersion) {
          return false;
        }
        final signalDate = _date(snapshot.signalTradeDate);
        if (startTradeDate != null &&
            signalDate.isBefore(_date(startTradeDate!))) {
          return false;
        }
        if (endTradeDate != null && signalDate.isAfter(_date(endTradeDate!))) {
          return false;
        }
        return true;
      }).toList(growable: false);

  bool _matchesSource(String source) => switch (sourceGroup) {
        DecisionArchiveSourceGroup.manual =>
          source == 'archive' || source == 'archive_backfill',
        DecisionArchiveSourceGroup.scan =>
          source == 'explore' || source == 'opportunity',
        DecisionArchiveSourceGroup.all => true,
      };

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
