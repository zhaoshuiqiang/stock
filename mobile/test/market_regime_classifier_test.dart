import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/market_regime_classifier.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('MarketRegimeClassifier', () {
    test('classifies missing market context as unknown with a data flag', () {
      final result = MarketRegimeClassifier.classify(null);

      expect(result.marketRegime, MarketRegime.unknown);
      expect(result.marketBias, 0);
      expect(result.dataQualityFlags, contains('market_context_missing'));
    });

    test('classifies invalid market values as unknown', () {
      final result = MarketRegimeClassifier.classify(
        _context(shIndexPct: double.nan),
      );

      expect(result.marketRegime, MarketRegime.unknown);
      expect(result.marketBias, 0);
      expect(result.dataQualityFlags, contains('market_context_invalid'));
    });

    test('prioritizes high volatility for index disagreement', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'up',
          shIndexPct: 1.2,
          szIndexPct: -0.4,
          avgChangePct: 0.9,
          upCount: 2600,
          downCount: 1900,
        ),
      );

      expect(result.marketRegime, MarketRegime.highVolatility);
      expect(result.marketBias, 0);
    });

    test('prioritizes high volatility for breadth price divergence', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'strong_up',
          shIndexPct: 1.3,
          szIndexPct: 1.1,
          avgChangePct: 1.4,
          upCount: 1500,
          downCount: 3000,
        ),
      );

      expect(result.marketRegime, MarketRegime.highVolatility);
      expect(result.marketBias, 0);
    });

    test('classifies confirmed positive market data as bullish trend', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'strong_up',
          shIndexPct: 1.3,
          szIndexPct: 1.1,
          avgChangePct: 1.2,
          upCount: 3600,
          downCount: 900,
        ),
      );

      expect(result.marketRegime, MarketRegime.bullishTrend);
      expect(result.marketBias, 50);
    });

    test('classifies positive recovery without full confirmation as rebound',
        () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'down',
          shIndexPct: 0.4,
          szIndexPct: 0.5,
          avgChangePct: 0.45,
          upCount: 2500,
          downCount: 1800,
        ),
      );

      expect(result.marketRegime, MarketRegime.rebound);
      expect(result.marketBias, 25);
    });

    test('classifies confirmed negative market data as bearish trend', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'strong_down',
          shIndexPct: -1.4,
          szIndexPct: -1.2,
          avgChangePct: -1.3,
          upCount: 800,
          downCount: 3700,
        ),
      );

      expect(result.marketRegime, MarketRegime.bearishTrend);
      expect(result.marketBias, -50);
    });

    test('classifies mild negative market data as pullback', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'down',
          shIndexPct: -0.35,
          szIndexPct: -0.25,
          avgChangePct: -0.45,
          upCount: 1800,
          downCount: 2500,
        ),
      );

      expect(result.marketRegime, MarketRegime.pullback);
      expect(result.marketBias, -20);
    });

    test('classifies neutral values as range', () {
      final result = MarketRegimeClassifier.classify(
        _context(
          marketTrend: 'neutral',
          shIndexPct: 0.08,
          szIndexPct: -0.06,
          avgChangePct: 0.03,
          upCount: 2200,
          downCount: 2100,
        ),
      );

      expect(result.marketRegime, MarketRegime.range);
      expect(result.marketBias, 0);
    });
  });
}

MarketContext _context({
  double shIndexPct = 0,
  double szIndexPct = 0,
  double indexChange = 0,
  String marketTrend = 'neutral',
  int upCount = 2200,
  int downCount = 2100,
  double avgChangePct = 0,
}) {
  return MarketContext(
    shIndexPct: shIndexPct,
    szIndexPct: szIndexPct,
    indexChange: indexChange,
    marketTrend: marketTrend,
    upCount: upCount,
    downCount: downCount,
    avgChangePct: avgChangePct,
    updateTime: DateTime.utc(2026, 7, 14),
  );
}
