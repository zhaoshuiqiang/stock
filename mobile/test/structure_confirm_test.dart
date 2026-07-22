import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/confidence_calculator.dart';
import 'package:stock_analyzer/analysis/market_structure_analyzer.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

/// v4.13: the confidence-breakdown "structure_confirm" dimension used to be a
/// verbatim copy of "market_confirm" (both = marketEnvironment), so the decision
/// page showed two identical rows. It now reflects the market STRUCTURE
/// alignment with the direction, independently.
MarketStructureResult _ms(MarketStructure s, double conf) =>
    MarketStructureResult(
      structure: s,
      confidence: conf,
      adxValue: 30,
      maAlignment: '',
      description: '',
      compatibleStrategies: const [],
      structureScore: 8,
    );

void main() {
  group('confidence breakdown structure_confirm', () {
    test('neutral 0.5 when market structure is unknown/null', () {
      final bd = ConfidenceCalculator.breakdown(
        buySignals: const [],
        sellSignals: const [],
        direction: RecommendationDirection.bullish,
      );
      expect(bd['structure_confirm'], closeTo(0.5, 1e-9));
    });

    test('rises for a bull structure aligned with a bullish direction', () {
      final bd = ConfidenceCalculator.breakdown(
        buySignals: const [],
        sellSignals: const [],
        direction: RecommendationDirection.bullish,
        marketStructure: _ms(MarketStructure.bullTrend, 0.8),
      );
      expect(bd['structure_confirm']!, greaterThan(0.5)); // 50 + 40*0.8 = 82
    });

    test('is no longer a verbatim duplicate of market_confirm', () {
      final bd = ConfidenceCalculator.breakdown(
        buySignals: const [],
        sellSignals: const [],
        direction: RecommendationDirection.bullish,
        marketStructure: _ms(MarketStructure.bullTrend, 0.8),
      );
      expect(bd['structure_confirm'],
          isNot(closeTo(bd['market_confirm']!, 1e-9)));
    });

    test('falls for a bear structure opposing a bullish direction', () {
      final bd = ConfidenceCalculator.breakdown(
        buySignals: const [],
        sellSignals: const [],
        direction: RecommendationDirection.bullish,
        marketStructure: _ms(MarketStructure.bearTrend, 0.8),
      );
      expect(bd['structure_confirm']!, lessThan(0.5)); // 50 - 40*0.8 = 18
    });
  });
}
