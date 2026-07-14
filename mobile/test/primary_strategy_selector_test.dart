import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/primary_strategy_selector.dart';
import 'package:stock_analyzer/analysis/strategy_engine.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

void main() {
  group('PrimaryStrategySelector', () {
    test(
        'ignores inactive, long-only, opposite, and under-confidence strategies',
        () {
      final result = PrimaryStrategySelector.select(
        strategies: [
          _strategy('inactive', isActive: false, strength: 100),
          _strategy('long', strategyType: 'long', strength: 100),
          _strategy('sell', type: 'sell', strength: 100),
          _strategy('strict', minConfidence: 0.8, strength: 100),
          _strategy('eligible', strength: 60),
        ],
        direction: RecommendationDirection.bullish,
        evidenceConfidence: 70,
      );

      expect(result.primary?.id, 'eligible');
      expect(result.supportingIds, isEmpty);
    });

    test(
        'selects highest strength then reward-risk and returns remaining support',
        () {
      final result = PrimaryStrategySelector.select(
        strategies: [
          _strategy('lower', strength: 70, riskReward: 3),
          _strategy('primary', strength: 80, riskReward: 2.5),
          _strategy('tie-lower-rr', strength: 80, riskReward: 2),
          _strategy('both', strategyType: 'both', strength: 65),
        ],
        direction: RecommendationDirection.bullish,
        evidenceConfidence: 75,
      );

      expect(result.primary?.id, 'primary');
      expect(result.supportingIds, ['tie-lower-rr', 'lower', 'both']);
    });

    test('bearish decisions accept sell strategies and neutral selects none',
        () {
      final strategies = [
        _strategy('buy', type: 'buy'),
        _strategy('sell', type: 'sell'),
      ];

      final bearish = PrimaryStrategySelector.select(
        strategies: strategies,
        direction: RecommendationDirection.bearish,
        evidenceConfidence: 80,
      );
      final neutral = PrimaryStrategySelector.select(
        strategies: strategies,
        direction: RecommendationDirection.neutral,
        evidenceConfidence: 80,
      );

      expect(bearish.primary?.id, 'sell');
      expect(neutral.primary, isNull);
      expect(neutral.supportingIds, isEmpty);
    });

    test('uses id as deterministic final tie-breaker', () {
      final result = PrimaryStrategySelector.select(
        strategies: [
          _strategy('zeta', strength: 80, riskReward: 2),
          _strategy('alpha', strength: 80, riskReward: 2),
        ],
        direction: RecommendationDirection.bullish,
        evidenceConfidence: 80,
      );

      expect(result.primary?.id, 'alpha');
      expect(result.supportingIds, ['zeta']);
    });
  });
}

TradingStrategy _strategy(
  String id, {
  bool isActive = true,
  String type = 'buy',
  String strategyType = 'short',
  int strength = 70,
  double minConfidence = 0.6,
  double riskReward = 2,
}) {
  return TradingStrategy(
    id: id,
    name: id,
    category: 'test',
    description: '',
    entryRule: '',
    exitRule: '',
    stopLossRule: '',
    isActive: isActive,
    type: type,
    strategyType: strategyType,
    signalStrength: strength,
    minConfidence: minConfidence,
    riskRewardRatio: riskReward,
  );
}
