import '../models/short_term_decision.dart';
import 'strategy_engine.dart';

class StrategySelectionResult {
  final TradingStrategy? primary;
  final List<String> supportingIds;

  const StrategySelectionResult({
    required this.primary,
    required this.supportingIds,
  });
}

class PrimaryStrategySelector {
  static StrategySelectionResult select({
    required List<TradingStrategy> strategies,
    required RecommendationDirection direction,
    required double evidenceConfidence,
  }) {
    if (direction == RecommendationDirection.neutral) {
      return const StrategySelectionResult(primary: null, supportingIds: []);
    }

    final requiredType =
        direction == RecommendationDirection.bullish ? 'buy' : 'sell';
    final confidence = evidenceConfidence.clamp(0.0, 100.0) / 100;
    final eligible = strategies.where((strategy) {
      final shortTerm =
          strategy.strategyType == 'short' || strategy.strategyType == 'both';
      return strategy.isActive &&
          shortTerm &&
          strategy.type == requiredType &&
          confidence >= strategy.minConfidence;
    }).toList()
      ..sort((a, b) {
        final strength = b.signalStrength.compareTo(a.signalStrength);
        if (strength != 0) return strength;
        final rewardRisk = b.riskRewardRatio.compareTo(a.riskRewardRatio);
        if (rewardRisk != 0) return rewardRisk;
        return a.id.compareTo(b.id);
      });

    if (eligible.isEmpty) {
      return const StrategySelectionResult(primary: null, supportingIds: []);
    }
    return StrategySelectionResult(
      primary: eligible.first,
      supportingIds: eligible.skip(1).map((strategy) => strategy.id).toList(),
    );
  }
}
