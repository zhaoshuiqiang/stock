import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('MarketContext avgChangePct', () {
    test('avgChangePct is stored and retrieved correctly', () {
      final mc = MarketContext(
        shIndexPct: -1.5,
        szIndexPct: -1.3,
        indexChange: -1.4,
        marketTrend: 'down',
        upCount: 1000,
        downCount: 3500,
        avgChangePct: -1.58,
        updateTime: DateTime.now(),
      );
      expect(mc.avgChangePct, -1.58);
    });
  });

  group('MarketContext getMarketAdjustmentFactor', () {
    test('extreme bull (>2%, breadth<75%) returns 1.05', () {
      final mc = MarketContext(
        shIndexPct: 2.5,
        szIndexPct: 2.3,
        indexChange: 80,
        marketTrend: 'strong_up',
        upCount: 2000,
        downCount: 1500,
        avgChangePct: 2.5,
        updateTime: DateTime.now(),
      );
      // breadth=57% < 75%, so no neutralization, >2.0% → 1.05
      expect(mc.getMarketAdjustmentFactor(), 1.05);
    });

    test('moderate up (0.3~1.0%) returns 1.01', () {
      final mc = MarketContext(
        shIndexPct: 0.8,
        szIndexPct: 1.0,
        indexChange: 30,
        marketTrend: 'up',
        upCount: 2000,
        downCount: 1500,
        avgChangePct: 0.6,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 1.01);
    });

    test('slight up (-0.3~0.3%) returns 1.00', () {
      final mc = MarketContext(
        shIndexPct: 0.2,
        szIndexPct: 0.3,
        indexChange: 10,
        marketTrend: 'up',
        upCount: 1800,
        downCount: 1700,
        avgChangePct: 0.15,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 1.00);
    });

    test('neutral (-0.3~0.3%) returns 1.00', () {
      final mc = MarketContext(
        shIndexPct: 0.1,
        szIndexPct: -0.1,
        indexChange: 0,
        marketTrend: 'neutral',
        upCount: 1700,
        downCount: 1800,
        avgChangePct: -0.1,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 1.00);
    });

    test('slight decline (-0.3~-0.5%) returns 0.98', () {
      final mc = MarketContext(
        shIndexPct: -0.4,
        szIndexPct: -0.3,
        indexChange: -15,
        marketTrend: 'down',
        upCount: 1500,
        downCount: 2000,
        avgChangePct: -0.4,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 0.98);
    });

    test('moderate decline (-0.5~-1.0%) returns 0.95', () {
      final mc = MarketContext(
        shIndexPct: -0.8,
        szIndexPct: -0.7,
        indexChange: -30,
        marketTrend: 'down',
        upCount: 1200,
        downCount: 2300,
        avgChangePct: -0.75,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 0.95);
    });

    test('significant decline (-1.0~-2.0%) returns 0.90', () {
      final mc = MarketContext(
        shIndexPct: -1.5,
        szIndexPct: -1.3,
        indexChange: -50,
        marketTrend: 'strong_down',
        upCount: 1000,
        downCount: 3500,
        avgChangePct: -1.58,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 0.90);
    });

    test('severe decline (-2.0~-3.0%) returns 0.85', () {
      final mc = MarketContext(
        shIndexPct: -2.5,
        szIndexPct: -2.3,
        indexChange: -80,
        marketTrend: 'strong_down',
        upCount: 500,
        downCount: 4000,
        avgChangePct: -2.5,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 0.85);
    });

    test('crash (<-3.0%) returns 0.80', () {
      final mc = MarketContext(
        shIndexPct: -4.0,
        szIndexPct: -3.5,
        indexChange: -120,
        marketTrend: 'strong_down',
        upCount: 200,
        downCount: 4800,
        avgChangePct: -3.8,
        updateTime: DateTime.now(),
      );
      expect(mc.getMarketAdjustmentFactor(), 0.80);
    });

    test('extreme breadth bull prevents excessive boost', () {
      final mc = MarketContext(
        shIndexPct: 3.0,
        szIndexPct: 2.5,
        indexChange: 100,
        marketTrend: 'strong_up',
        upCount: 4000,
        downCount: 500,
        avgChangePct: 2.5,
        updateTime: DateTime.now(),
      );
      // breadth=0.89 & avgChangePct=2.5 > 1.0 => neutralized to 1.0
      expect(mc.getMarketAdjustmentFactor(), 1.0);
    });
  });
}
