import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'backtest_engine.dart';
import 'market_structure_analyzer.dart';

class EvidenceConfidenceResult {
  final double score;
  final Map<String, double> components;

  const EvidenceConfidenceResult({
    required this.score,
    required this.components,
  });

  double get componentAgreement => components['component_agreement'] ?? 0;
  double get dataCoverage => components['data_coverage'] ?? 0;
  double get freshness => components['freshness'] ?? 0;
  double get historyStability => components['history_stability'] ?? 0;
  double get fundamentalSupport => components['fundamental_support'] ?? 0;
  double get sentimentConfirm => components['sentiment_confirm'] ?? 0;
  double get marketEnvironment => components['market_environment'] ?? 0;
  double get backtestWinRate => components['backtest_winrate'] ?? 0;
}

class EvidenceConfidenceCalculator {
  static const Map<String, double> weights = {
    'component_agreement': 0.25,
    'data_coverage': 0.20,
    'freshness': 0.15,
    'history_stability': 0.10,
    'fundamental_support': 0.10,
    'sentiment_confirm': 0.08,
    'market_environment': 0.07,
    'backtest_winrate': 0.05,
  };

  static EvidenceConfidenceResult calculate({
    required Map<String, double> directionComponents,
    required List<SignalItem> directionalSignals,
    required List<String> dataQualityFlags,
    double historicalStability = 50,
    FundamentalScore? fundamentalScore,
    NewsSentiment? newsSentiment,
    MarketContext? marketContext,
    MarketStructureResult? marketStructure,
    Map<String, BacktestResult>? backtestResults,
    RecommendationDirection? direction,
    DateTime? now,
  }) {
    final resolvedDirection = direction ?? _inferDirection(directionComponents);
    final components = <String, double>{
      'component_agreement': _agreement(directionComponents),
      'data_coverage': _coverage(directionComponents, dataQualityFlags),
      'freshness': _freshness(directionalSignals, now ?? DateTime.now()),
      'history_stability': historicalStability,
      'fundamental_support': _fundamentalSupport(fundamentalScore, resolvedDirection),
      'sentiment_confirm': _sentimentConfirm(newsSentiment, resolvedDirection),
      'market_environment': _marketEnvironment(marketContext, marketStructure, resolvedDirection),
      'backtest_winrate': _backtestWinRate(backtestResults),
    }.map((key, value) => MapEntry(key, _bounded(value)));
    final score = components.entries.fold<double>(
      0,
      (sum, entry) => sum + entry.value * weights[entry.key]!,
    );
    return EvidenceConfidenceResult(
      score: _bounded(score),
      components: Map.unmodifiable(components),
    );
  }

  static RecommendationDirection _inferDirection(Map<String, double> components) {
    final sum = components.values.fold<double>(0, (a, b) => a + b);
    if (sum >= 0.15) return RecommendationDirection.bullish;
    if (sum <= -0.15) return RecommendationDirection.bearish;
    return RecommendationDirection.neutral;
  }

  static double _fundamentalSupport(FundamentalScore? fs, RecommendationDirection dir) {
    if (fs == null) return 50;
    if (dir == RecommendationDirection.bullish && fs.totalScore >= 6) {
      return (70 + (fs.totalScore - 6) * 10).clamp(0.0, 100.0);
    }
    if (dir == RecommendationDirection.bearish && fs.totalScore <= 4) {
      return (70 + (4 - fs.totalScore) * 10).clamp(0.0, 100.0);
    }
    if (dir == RecommendationDirection.bullish && fs.totalScore < 4) return 30;
    if (dir == RecommendationDirection.bearish && fs.totalScore > 6) return 30;
    return 50;
  }

  static double _sentimentConfirm(NewsSentiment? ns, RecommendationDirection dir) {
    if (ns == null) return 50;
    if (dir == RecommendationDirection.bullish && ns.score > 2) {
      return (70 + (ns.score - 2) * 3).clamp(0.0, 100.0);
    }
    if (dir == RecommendationDirection.bearish && ns.score < -2) {
      return (70 + (-2 - ns.score) * 3).clamp(0.0, 100.0);
    }
    if (dir == RecommendationDirection.bullish && ns.score < -2) return 30;
    if (dir == RecommendationDirection.bearish && ns.score > 2) return 30;
    return 50;
  }

  static double _marketEnvironment(
    MarketContext? mc,
    MarketStructureResult? ms,
    RecommendationDirection dir,
  ) {
    var score = 50.0;
    if (mc != null) {
      if (dir == RecommendationDirection.bullish && mc.avgChangePct > 0.5) score += 20;
      else if (dir == RecommendationDirection.bearish && mc.avgChangePct < -0.5) score += 20;
      else if (dir == RecommendationDirection.bullish && mc.avgChangePct < -1) score -= 20;
      else if (dir == RecommendationDirection.bearish && mc.avgChangePct > 1) score -= 20;
    }
    if (ms != null) {
      final isBullish = ms.structure == MarketStructure.bullTrend ||
          ms.structure == MarketStructure.accumulation;
      final isBearish = ms.structure == MarketStructure.bearTrend ||
          ms.structure == MarketStructure.distribution;
      if (dir == RecommendationDirection.bullish && isBullish) score += 15;
      else if (dir == RecommendationDirection.bearish && isBearish) score += 15;
      else if (dir == RecommendationDirection.bullish && isBearish) score -= 15;
      else if (dir == RecommendationDirection.bearish && isBullish) score -= 15;
    }
    return score;
  }

  static double _backtestWinRate(Map<String, BacktestResult>? results) {
    if (results == null || results.isEmpty) return 50;
    final winRates = results.values
        .where((r) => r.totalSignals > 0 && r.winRate > 0)
        .map((r) => r.winRate)
        .toList();
    if (winRates.isEmpty) return 50;
    final avg = winRates.reduce((a, b) => a + b) / winRates.length;
    return (30 + avg * 70).clamp(0.0, 100.0);
  }

  static double _agreement(Map<String, double> components) {
    final meaningful = components.values
        .where((value) => value.isFinite && value.abs() >= 0.05)
        .toList();
    if (meaningful.isEmpty) return 25;
    final positive = meaningful
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final negative = meaningful
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final total = positive + negative;
    if (total == 0) return 25;
    final dominantShare = (positive > negative ? positive : negative) / total;
    final breadth = (meaningful.length / 5).clamp(0.0, 1.0);
    return dominantShare * 80 + breadth * 20;
  }

  static double _coverage(
    Map<String, double> components,
    List<String> dataQualityFlags,
  ) {
    final covered = components.values
        .where((value) => value.isFinite && value.abs() >= 0.01)
        .length;
    var score = (covered / 5).clamp(0.0, 1.0) * 100;
    for (final flag in dataQualityFlags.toSet()) {
      score -= flag == 'evidence_family_conflict'
          ? 15
          : flag.contains('missing')
              ? 18
              : 10;
    }
    return score;
  }

  static double _freshness(List<SignalItem> signals, DateTime now) {
    if (signals.isEmpty) return 35;
    var total = 0.0;
    for (final signal in signals) {
      final date = signal.freshTime ?? signal.timestamp;
      final ageHours = date == null
          ? 24 * 7
          : now.difference(date).inHours.clamp(0, 24 * 30);
      final ageScore = ageHours <= 24
          ? 100.0
          : ageHours <= 72
              ? 80.0
              : ageHours <= 120
                  ? 60.0
                  : 30.0;
      final confidence = (signal.confidence ?? 0.6).clamp(0.0, 1.0) * 100;
      total += ageScore * 0.7 + confidence * 0.3;
    }
    return total / signals.length;
  }

  static double _bounded(double value) => value.clamp(0.0, 100.0).toDouble();
}
