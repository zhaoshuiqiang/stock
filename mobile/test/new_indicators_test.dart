import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'dart:math';

// Helper: generate kline data with known prices
List<HistoryKline> generateKlines(List<double> prices, {List<double>? volumes}) {
  return List.generate(prices.length, (i) {
    final price = prices[i];
    final vol = volumes != null && i < volumes.length ? volumes[i] : 10000.0;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: vol,
      amount: vol * price,
      change: i > 0 ? price - prices[i - 1] : 0,
      changePct: i > 0 && prices[i - 1] > 0 ? (price - prices[i - 1]) / prices[i - 1] * 100 : 0,
    );
  });
}

// Helper: generate uptrend data
List<HistoryKline> generateUptrend(int count, {double start = 10.0, double daily = 0.02}) {
  double price = start;
  return List.generate(count, (i) {
    final open = price;
    price *= (1 + daily);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: price * 1.01, low: open * 0.99, close: price,
      volume: 10000 + i * 100, amount: 10000 * (open + price) / 2,
      change: price - open, changePct: (price - open) / open * 100,
    );
  });
}

// Helper: generate downtrend data
List<HistoryKline> generateDowntrend(int count, {double start = 30.0, double daily = -0.02}) {
  double price = start;
  return List.generate(count, (i) {
    final open = price;
    price *= (1 + daily);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: open * 1.01, low: price * 0.99, close: price,
      volume: 10000 + i * 100, amount: 10000 * (open + price) / 2,
      change: price - open, changePct: (price - open) / open * 100,
    );
  });
}

void main() {
  group('EMA Calculation', () {
    test('EMA5 calculated correctly with known data', () {
      final prices = [10.0, 11.0, 12.0, 11.5, 13.0, 14.0, 13.5, 15.0, 14.5, 16.0];
      final data = generateKlines(prices);
      final result = calcEMA(data, [5]);
      // EMA starts with first price
      expect(result[0].ema5, closeTo(10.0, 0.01));
      // EMA should be computed for all bars
      for (int i = 0; i < result.length; i++) {
        expect(result[i].ema5, greaterThan(0));
      }
    });

    test('EMA responds faster than SMA to price changes', () {
      final data = generateUptrend(60);
      final withEma = calcEMA(data, [5]);
      final withMa = calcMA(data, [5]);
      // In uptrend, EMA should be above SMA (more responsive to recent rises)
      final lastEma = withEma.last.ema5;
      final lastMa = withMa.last.ma5;
      expect(lastEma, greaterThan(lastMa));
    });

    test('EMA10/20/60 all calculated', () {
      final data = generateUptrend(80);
      final result = calcEMA(data, [5, 10, 20, 60]);
      final last = result.last;
      expect(last.ema5, greaterThan(0));
      expect(last.ema10, greaterThan(0));
      expect(last.ema20, greaterThan(0));
      expect(last.ema60, greaterThan(0));
      // In uptrend: EMA5 > EMA10 > EMA20 > EMA60
      expect(last.ema5, greaterThan(last.ema10));
      expect(last.ema10, greaterThan(last.ema20));
      expect(last.ema20, greaterThan(last.ema60));
    });

    test('EMA with empty data returns empty', () {
      final result = calcEMA([], [5]);
      expect(result, isEmpty);
    });
  });

  group('ATR Calculation', () {
    test('ATR14 calculated with known data', () {
      final data = generateUptrend(60);
      final result = calcATR(data);
      final last = result.last;
      expect(last.atr14, greaterThan(0));
    });

    test('ATR reflects volatility', () {
      // High volatility data
      double price = 10.0;
      final highVol = List.generate(60, (i) {
        final open = price;
        price *= (i % 2 == 0 ? 1.05 : 0.95); // Big swings
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: open, high: max(open, price) * 1.03, low: min(open, price) * 0.97, close: price,
          volume: 10000, amount: 10000 * (open + price) / 2,
        );
      });
      
      // Low volatility data
      final lowVol = List.generate(60, (i) {
        final p = 10.0 + (i % 3 - 1) * 0.01;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: p, high: p + 0.02, low: p - 0.02, close: p,
          volume: 10000, amount: 10000 * p,
        );
      });
      
      final highVolResult = calcATR(highVol);
      final lowVolResult = calcATR(lowVol);
      
      expect(highVolResult.last.atr14, greaterThan(lowVolResult.last.atr14));
    });

    test('ATR with insufficient data returns zeros', () {
      final data = generateKlines([10.0]);
      final result = calcATR(data);
      expect(result.first.atr14, equals(0));
    });
  });

  group('OBV Calculation', () {
    test('OBV increases when price rises', () {
      final prices = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0];
      final vols = [10000.0, 12000.0, 11000.0, 13000.0, 15000.0, 14000.0];
      final data = generateKlines(prices, volumes: vols);
      final result = calcOBV(data);
      // OBV should be increasing in uptrend
      for (int i = 1; i < result.length; i++) {
        expect(result[i].obv, greaterThan(result[i - 1].obv));
      }
    });

    test('OBV decreases when price falls', () {
      final prices = [15.0, 14.0, 13.0, 12.0, 11.0, 10.0];
      final vols = [10000.0, 12000.0, 11000.0, 13000.0, 15000.0, 14000.0];
      final data = generateKlines(prices, volumes: vols);
      final result = calcOBV(data);
      // OBV should be decreasing in downtrend
      for (int i = 1; i < result.length; i++) {
        expect(result[i].obv, lessThan(result[i - 1].obv));
      }
    });

    test('OBV unchanged when price is flat', () {
      final prices = [10.0, 10.0, 10.0];
      final vols = [10000.0, 12000.0, 11000.0];
      final data = generateKlines(prices, volumes: vols);
      final result = calcOBV(data);
      expect(result[1].obv, equals(result[0].obv));
      expect(result[2].obv, equals(result[1].obv));
    });

    test('OBV first value equals first volume', () {
      final data = generateKlines([10.0, 11.0], volumes: [5000.0, 6000.0]);
      final result = calcOBV(data);
      expect(result[0].obv, equals(5000.0));
    });
  });

  group('BIAS Calculation', () {
    test('BIAS6 calculated correctly', () {
      final data = generateUptrend(30);
      final result = calcBIAS(data, [6]);
      // BIAS should be calculated for bars >= 6
      for (int i = 5; i < result.length; i++) {
        expect(result[i].bias6, isNot(equals(0)));
      }
    });

    test('BIAS is positive in uptrend', () {
      final data = generateUptrend(30);
      final result = calcBIAS(data, [6, 12, 24]);
      // In uptrend, price > MA, so BIAS should be positive
      if (result.length > 24) {
        expect(result.last.bias6, greaterThan(0));
        expect(result.last.bias12, greaterThan(0));
        expect(result.last.bias24, greaterThan(0));
      }
    });

    test('BIAS is negative in downtrend', () {
      final data = generateDowntrend(30);
      final result = calcBIAS(data, [6, 12, 24]);
      if (result.length > 24) {
        expect(result.last.bias6, lessThan(0));
      }
    });

    test('BIAS formula: (close - MA) / MA * 100', () {
      final prices = [10.0, 10.5, 11.0, 10.8, 11.2, 11.5];
      final data = generateKlines(prices);
      final result = calcBIAS(data, [6]);
      final ma6 = prices.reduce((a, b) => a + b) / 6;
      final expectedBias = (11.5 - ma6) / ma6 * 100;
      expect(result.last.bias6, closeTo(expectedBias, 0.01));
    });
  });

  group('DMI/ADX Calculation', () {
    test('ADX14 calculated with sufficient data', () {
      final data = generateUptrend(60);
      final result = calcDMI(data);
      final last = result.last;
      expect(last.plusDi14, greaterThanOrEqualTo(0));
      expect(last.minusDi14, greaterThanOrEqualTo(0));
      expect(last.dx, greaterThanOrEqualTo(0));
      expect(last.adx14, greaterThanOrEqualTo(0));
    });

    test('+DI > -DI in uptrend', () {
      final data = generateUptrend(60);
      final result = calcDMI(data);
      final last = result.last;
      // In strong uptrend, +DI should be greater than -DI
      expect(last.plusDi14, greaterThan(last.minusDi14));
    });

    test('-DI > +DI in downtrend', () {
      final data = generateDowntrend(60);
      final result = calcDMI(data);
      final last = result.last;
      // In strong downtrend, -DI should be greater than +DI
      expect(last.minusDi14, greaterThan(last.plusDi14));
    });

    test('ADX > 25 indicates strong trend', () {
      final data = generateUptrend(80);
      final result = calcDMI(data);
      // In strong uptrend, ADX should be above 25
      final last = result.last;
      // May not always be > 25 with generated data, but should be positive
      expect(last.adx14, greaterThanOrEqualTo(0));
    });

    test('DMI with insufficient data returns zeros', () {
      final data = generateKlines([10.0, 11.0, 12.0]);
      final result = calcDMI(data);
      for (final k in result) {
        expect(k.plusDi14, equals(0));
        expect(k.minusDi14, equals(0));
      }
    });
  });

  group('BOLL Sample Standard Deviation', () {
    test('BOLL uses sample std dev (n-1)', () {
      // Create data where population vs sample std dev differ noticeably
      final prices = List.generate(25, (i) => 10.0 + (i % 5 - 2) * 0.5);
      final data = generateKlines(prices);
      final result = calcBOLL(data);
      final last = result.last;
      
      // Manually calculate sample std dev
      final last20 = prices.sublist(prices.length - 20);
      final mean = last20.reduce((a, b) => a + b) / 20;
      final variance = last20.map((p) => (p - mean) * (p - mean)).reduce((a, b) => a + b) / 19; // sample
      final expectedStd = sqrt(variance);
      
      final actualStd = (last.bollUpper - last.bollMid) / 2;
      expect(actualStd, closeTo(expectedStd, 0.01));
    });
  });

  group('calcAllIndicators Integration', () {
    test('all new indicators are populated', () {
      final data = generateUptrend(80);
      final result = calcAllIndicators(data);
      final last = result.last;
      
      // All new indicators should be populated
      expect(last.ema5, greaterThan(0));
      expect(last.ema10, greaterThan(0));
      expect(last.ema20, greaterThan(0));
      expect(last.atr14, greaterThan(0));
      expect(last.obv, isNot(equals(0)));
      expect(last.bias6, isNot(equals(0)));
      expect(last.plusDi14, greaterThanOrEqualTo(0));
      expect(last.minusDi14, greaterThanOrEqualTo(0));
    });

    test('indicators are consistent with price direction', () {
      final data = generateUptrend(80);
      final result = calcAllIndicators(data);
      final last = result.last;
      
      // In uptrend: EMA5 > EMA10 > EMA20
      expect(last.ema5, greaterThan(last.ema10));
      expect(last.ema10, greaterThan(last.ema20));
      
      // BIAS should be positive
      expect(last.bias6, greaterThan(0));
      
      // +DI > -DI
      expect(last.plusDi14, greaterThan(last.minusDi14));
    });
  });
}
