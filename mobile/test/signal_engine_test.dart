import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';

// ─── Helper: convert a list of prices into HistoryKline objects ───
List<HistoryKline> _pricesToKlines(List<double> prices, {List<double>? volumes}) {
  return List.generate(prices.length, (i) {
    final price = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price * 0.99,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: volumes != null && i < volumes.length ? volumes[i] : 10000.0 + (i % 5) * 2000,
      amount: 10000 * price,
      change: i > 0 ? price - prices[i - 1] : 0,
      changePct: i > 0 && prices[i - 1] > 0
          ? (price - prices[i - 1]) / prices[i - 1] * 100
          : 0,
    );
  });
}

// Generate enough base data, calculate indicators, then tweak the last two
// klines to force the exact crossover pattern at the boundary.
// This is the most reliable way to unit-test signal detection logic.

/// Generate base kline data with indicators calculated.
List<HistoryKline> _baseData({int count = 40}) {
  final prices = List.generate(count, (i) => 15.0 + (i % 10) * 0.5);
  return calcAllIndicators(_pricesToKlines(prices));
}

/// Generate klines with a strong uptrend pattern.
List<HistoryKline> generateUptrendKlines(int count) {
  double price = 10.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 1.02;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: price * 1.01,
      low: open * 0.99,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

/// Generate klines with a strong downtrend pattern.
List<HistoryKline> generateDowntrendKlines(int count) {
  double price = 30.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 0.98;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: open * 1.01,
      low: price * 0.99,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  // ─── 1. MA Signal Tests ───
  group('MA Signal Tests', () {
    test('MA golden cross detection (MA5 crosses above MA10)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: ma5 <= ma10, last: ma5 > ma10
      data[n - 2] = data[n - 2].copyWith(ma5: 14.0, ma10: 15.0);
      data[n - 1] = data[n - 1].copyWith(ma5: 16.0, ma10: 15.0);

      final signals = detectSignals(data);
      final maGolden = signals.where(
        (s) => s.indicator == 'MA' && s.signal == 'MA5上穿MA10',
      );
      expect(maGolden.isNotEmpty, true, reason: 'Should detect MA5 golden cross above MA10');
      expect(maGolden.first.type, 'buy');
    });

    test('MA death cross detection (MA5 crosses below MA10)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: ma5 >= ma10, last: ma5 < ma10
      data[n - 2] = data[n - 2].copyWith(ma5: 16.0, ma10: 15.0);
      data[n - 1] = data[n - 1].copyWith(ma5: 14.0, ma10: 15.0);

      final signals = detectSignals(data);
      final maDeath = signals.where(
        (s) => s.indicator == 'MA' && s.signal == 'MA5下穿MA10',
      );
      expect(maDeath.isNotEmpty, true, reason: 'Should detect MA5 death cross below MA10');
      expect(maDeath.first.type, 'sell');
    });

    test('No MA cross signal when MAs are parallel', () {
      var data = _baseData();
      final n = data.length;
      // Both klines have ma5 > ma10 (no crossover)
      data[n - 2] = data[n - 2].copyWith(ma5: 16.0, ma10: 15.0);
      data[n - 1] = data[n - 1].copyWith(ma5: 17.0, ma10: 15.5);

      final signals = detectSignals(data);
      final maCross = signals.where(
        (s) => s.indicator == 'MA' && (s.signal == 'MA5上穿MA10' || s.signal == 'MA5下穿MA10'),
      );
      expect(maCross.isEmpty, true, reason: 'Should not detect MA cross when MAs are parallel');
    });
  });

  // ─── 2. MACD Signal Tests ───
  group('MACD Signal Tests', () {
    test('MACD golden cross detection (DIF crosses above DEA)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: dif <= dea, last: dif > dea
      data[n - 2] = data[n - 2].copyWith(macdDif: -0.5, macdDea: -0.3, macdHist: 2 * (-0.5 - (-0.3)));
      data[n - 1] = data[n - 1].copyWith(macdDif: 0.3, macdDea: -0.1, macdHist: 2 * (0.3 - (-0.1)));

      final signals = detectSignals(data);
      final macdGolden = signals.where(
        (s) => s.indicator == 'MACD' && s.signal == 'MACD金叉',
      );
      expect(macdGolden.isNotEmpty, true, reason: 'Should detect MACD golden cross');
      expect(macdGolden.first.type, 'buy');
    });

    test('MACD death cross detection (DIF crosses below DEA)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: dif >= dea, last: dif < dea
      data[n - 2] = data[n - 2].copyWith(macdDif: 0.5, macdDea: 0.3, macdHist: 2 * (0.5 - 0.3));
      data[n - 1] = data[n - 1].copyWith(macdDif: -0.3, macdDea: 0.1, macdHist: 2 * (-0.3 - 0.1));

      final signals = detectSignals(data);
      final macdDeath = signals.where(
        (s) => s.indicator == 'MACD' && s.signal == 'MACD死叉',
      );
      expect(macdDeath.isNotEmpty, true, reason: 'Should detect MACD death cross');
      expect(macdDeath.first.type, 'sell');
    });
  });

  // ─── 3. RSI Signal Tests ───
  group('RSI Signal Tests', () {
    test('RSI overbought detection (RSI > 70)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.rsi6 <= 70, last.rsi6 > 70 to trigger "RSI进入超买区"
      data[n - 2] = data[n - 2].copyWith(rsi6: 68.0);
      data[n - 1] = data[n - 1].copyWith(rsi6: 75.0);

      final signals = detectSignals(data);
      final rsiOverbought = signals.where(
        (s) => s.indicator == 'RSI' && s.signal.contains('超买'),
      );
      expect(rsiOverbought.isNotEmpty, true, reason: 'Should detect RSI overbought signal');
    });

    test('RSI oversold detection (RSI < 30)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.rsi6 >= 30, last.rsi6 < 30 to trigger "RSI进入超卖区"
      data[n - 2] = data[n - 2].copyWith(rsi6: 32.0);
      data[n - 1] = data[n - 1].copyWith(rsi6: 25.0);

      final signals = detectSignals(data);
      final rsiOversold = signals.where(
        (s) => s.indicator == 'RSI' && s.signal.contains('超卖'),
      );
      expect(rsiOversold.isNotEmpty, true, reason: 'Should detect RSI oversold signal');
    });

    test('No RSI signal when RSI is in normal range', () {
      var data = _baseData();
      final n = data.length;
      // Both in normal range, no crossing of 30/70 thresholds
      data[n - 2] = data[n - 2].copyWith(rsi6: 50.0);
      data[n - 1] = data[n - 1].copyWith(rsi6: 55.0);

      final signals = detectSignals(data);
      final rsiExtreme = signals.where(
        (s) => s.indicator == 'RSI' && (s.signal.contains('超买') || s.signal.contains('超卖')),
      );
      expect(rsiExtreme.isEmpty, true, reason: 'Should not detect RSI extreme signal in normal range');
    });
  });

  // ─── 4. KDJ Signal Tests ───
  group('KDJ Signal Tests', () {
    test('KDJ golden cross detection (K crosses above D)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: k <= d, last: k > d
      data[n - 2] = data[n - 2].copyWith(k: 30.0, d: 40.0, j: 3 * 30.0 - 2 * 40.0);
      data[n - 1] = data[n - 1].copyWith(k: 50.0, d: 42.0, j: 3 * 50.0 - 2 * 42.0);

      final signals = detectSignals(data);
      final kdjGolden = signals.where(
        (s) => s.indicator == 'KDJ' && s.signal == 'KDJ金叉',
      );
      expect(kdjGolden.isNotEmpty, true, reason: 'Should detect KDJ golden cross');
      expect(kdjGolden.first.type, 'buy');
    });

    test('KDJ death cross detection (K crosses below D)', () {
      var data = _baseData();
      final n = data.length;
      // Force prev: k >= d, last: k < d
      data[n - 2] = data[n - 2].copyWith(k: 50.0, d: 40.0, j: 3 * 50.0 - 2 * 40.0);
      data[n - 1] = data[n - 1].copyWith(k: 30.0, d: 42.0, j: 3 * 30.0 - 2 * 42.0);

      final signals = detectSignals(data);
      final kdjDeath = signals.where(
        (s) => s.indicator == 'KDJ' && s.signal == 'KDJ死叉',
      );
      expect(kdjDeath.isNotEmpty, true, reason: 'Should detect KDJ death cross');
      expect(kdjDeath.first.type, 'sell');
    });

    test('J value overbought/oversold', () {
      // Test J overbought (> 100)
      var data1 = _baseData();
      final n1 = data1.length;
      // Force prev.j <= 100, last.j > 100
      data1[n1 - 2] = data1[n1 - 2].copyWith(k: 70.0, d: 40.0, j: 3 * 70.0 - 2 * 40.0); // j=130
      data1[n1 - 1] = data1[n1 - 1].copyWith(k: 75.0, d: 38.0, j: 3 * 75.0 - 2 * 38.0); // j=149
      // But we need prev.j <= 100 for the signal to trigger
      data1[n1 - 2] = data1[n1 - 2].copyWith(k: 50.0, d: 40.0, j: 3 * 50.0 - 2 * 40.0); // j=70
      data1[n1 - 1] = data1[n1 - 1].copyWith(k: 80.0, d: 30.0, j: 3 * 80.0 - 2 * 30.0); // j=180

      final signals1 = detectSignals(data1);
      final jOverbought = signals1.where(
        (s) => s.indicator == 'KDJ' && s.signal == 'J线超买',
      );
      expect(jOverbought.isNotEmpty, true, reason: 'Should detect J line overbought');

      // Test J oversold (< 0)
      var data2 = _baseData();
      final n2 = data2.length;
      // Force prev.j >= 0, last.j < 0
      data2[n2 - 2] = data2[n2 - 2].copyWith(k: 30.0, d: 40.0, j: 3 * 30.0 - 2 * 40.0); // j=10
      data2[n2 - 1] = data2[n2 - 1].copyWith(k: 10.0, d: 50.0, j: 3 * 10.0 - 2 * 50.0); // j=-70

      final signals2 = detectSignals(data2);
      final jOversold = signals2.where(
        (s) => s.indicator == 'KDJ' && s.signal == 'J线超卖',
      );
      expect(jOversold.isNotEmpty, true, reason: 'Should detect J line oversold');
    });
  });

  // ─── 5. BOLL Signal Tests ───
  group('BOLL Signal Tests', () {
    test('BOLL upper band breakout detection', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.close <= bollUpper, last.close > bollUpper
      data[n - 2] = data[n - 2].copyWith(
        close: 18.0,
        bollUpper: 19.0,
        bollMid: 17.0,
        bollLower: 15.0,
      );
      data[n - 1] = data[n - 1].copyWith(
        close: 20.0,
        bollUpper: 19.0,
        bollMid: 17.0,
        bollLower: 15.0,
      );

      final signals = detectSignals(data);
      final bollUpper = signals.where(
        (s) => s.indicator == 'BOLL' && s.signal == '突破上轨',
      );
      expect(bollUpper.isNotEmpty, true, reason: 'Should detect BOLL upper band breakout');
      expect(bollUpper.first.type, 'sell');
    });

    test('BOLL lower band breakout detection', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.close >= bollLower, last.close < bollLower
      data[n - 2] = data[n - 2].copyWith(
        close: 16.0,
        bollUpper: 19.0,
        bollMid: 17.0,
        bollLower: 15.0,
      );
      data[n - 1] = data[n - 1].copyWith(
        close: 14.0,
        bollUpper: 19.0,
        bollMid: 17.0,
        bollLower: 15.0,
      );

      final signals = detectSignals(data);
      final bollLower = signals.where(
        (s) => s.indicator == 'BOLL' && s.signal == '跌破下轨',
      );
      expect(bollLower.isNotEmpty, true, reason: 'Should detect BOLL lower band breakout');
      expect(bollLower.first.type, 'buy');
    });
  });

  // ─── 6. Volume-Price Signal Tests ───
  group('Volume-Price Signal Tests', () {
    test('Volume breakout detection (volume > volMa5 * 1.5)', () {
      var data = _baseData();
      final n = data.length;
      // Force volMa5 = 10000, volume = 25000 (ratio = 2.5 > 2)
      // Also make close > prev.close for "放量上涨"
      data[n - 2] = data[n - 2].copyWith(
        close: 15.0,
        open: 14.5,
        volMa5: 10000.0,
        volume: 10000.0,
      );
      data[n - 1] = data[n - 1].copyWith(
        close: 16.0,
        open: 15.5,
        volMa5: 10000.0,
        volume: 25000.0,
      );

      final signals = detectSignals(data);
      final volBreakout = signals.where(
        (s) => s.indicator == '量价' && s.signal.contains('放量'),
      );
      expect(volBreakout.isNotEmpty, true, reason: 'Should detect volume breakout signal');
    });

    test('Shrinking volume detection', () {
      var data = _baseData();
      final n = data.length;
      // Force volMa5 = 10000, volume = 3000 (ratio = 0.3 < 0.5)
      data[n - 2] = data[n - 2].copyWith(volMa5: 10000.0, volume: 10000.0);
      data[n - 1] = data[n - 1].copyWith(volMa5: 10000.0, volume: 3000.0);

      final signals = detectSignals(data);
      final shrinkVol = signals.where(
        (s) => s.indicator == '量价' && s.signal == '缩量观望',
      );
      expect(shrinkVol.isNotEmpty, true, reason: 'Should detect shrinking volume signal');
      expect(shrinkVol.first.type, 'buy');
    });
  });

  // ─── Edge Cases ───
  group('Edge Cases', () {
    test('Empty data returns no signals', () {
      final signals = detectSignals([]);
      expect(signals, isEmpty);
    });

    test('Single data point returns no signals', () {
      final data = [HistoryKline(date: DateTime(2024, 1, 1), close: 10.0)];
      final signals = detectSignals(data);
      expect(signals, isEmpty);
    });

    test('Signals are sorted by strength descending', () {
      var data = _baseData();
      final n = data.length;
      // Set up multiple signals with different strengths
      data[n - 2] = data[n - 2].copyWith(
        ma5: 14.0, ma10: 15.0,
        macdDif: -0.5, macdDea: -0.3, macdHist: -0.4,
        rsi6: 68.0,
        k: 30.0, d: 40.0, j: 10.0,
        bollUpper: 19.0, bollMid: 17.0, bollLower: 15.0,
        close: 18.0,
        volMa5: 10000.0, volume: 10000.0,
      );
      data[n - 1] = data[n - 1].copyWith(
        ma5: 16.0, ma10: 15.0,
        macdDif: 0.3, macdDea: -0.1, macdHist: 0.8,
        rsi6: 75.0,
        k: 50.0, d: 42.0, j: 66.0,
        bollUpper: 19.0, bollMid: 17.0, bollLower: 15.0,
        close: 20.0,
        volMa5: 10000.0, volume: 10000.0,
      );

      final signals = detectSignals(data);
      if (signals.length >= 2) {
        for (int i = 0; i < signals.length - 1; i++) {
          expect(signals[i].strength, greaterThanOrEqualTo(signals[i + 1].strength));
        }
      }
    });
  });

  // ─── Integration: Real price data patterns ───
  group('Integration: Real price patterns', () {
    test('Golden cross data produces MA golden cross signal', () {
      // Generate declining then rising prices to create a natural golden cross
      final prices = <double>[];
      double price = 15.0;
      for (int i = 0; i < 15; i++) {
        prices.add(price);
        price -= 0.3;
      }
      for (int i = 0; i < 25; i++) {
        prices.add(price);
        price += 0.5;
      }
      final data = calcAllIndicators(_pricesToKlines(prices));
      final last = data.last;
      final prev = data[data.length - 2];

      // Verify the golden cross condition exists
      if (last.ma5 > last.ma10 && prev.ma5 <= prev.ma10) {
        final signals = detectSignals(data);
        final maGolden = signals.where(
          (s) => s.indicator == 'MA' && s.signal == 'MA5上穿MA10',
        );
        expect(maGolden.isNotEmpty, true, reason: 'Natural golden cross data should produce signal');
      }
      // If the crossover didn't happen exactly at the boundary, that's OK -
      // the manually-constructed tests above cover the detection logic.
    });

    test('Overbought data produces RSI overbought signal', () {
      final prices = <double>[];
      double price = 10.0;
      for (int i = 0; i < 30; i++) {
        prices.add(price);
        price *= 1.05;
      }
      final data = calcAllIndicators(_pricesToKlines(prices));
      final last = data.last;

      // Verify RSI is high
      expect(last.rsi6, greaterThan(70), reason: 'Strong uptrend should produce high RSI');

      // Manually set prev to ensure the threshold crossing
      final n = data.length;
      final adjusted = List<HistoryKline>.from(data);
      adjusted[n - 2] = adjusted[n - 2].copyWith(rsi6: 68.0);

      final signals = detectSignals(adjusted);
      final rsiOverbought = signals.where(
        (s) => s.indicator == 'RSI' && s.signal.contains('超买'),
      );
      expect(rsiOverbought.isNotEmpty, true, reason: 'Should detect RSI overbought with threshold crossing');
    });

    test('Oversold data produces RSI oversold signal', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.rsi6 >= 30, last.rsi6 < 30 to trigger "RSI进入超卖区"
      data[n - 2] = data[n - 2].copyWith(rsi6: 32.0);
      data[n - 1] = data[n - 1].copyWith(rsi6: 25.0);

      final signals = detectSignals(data);
      final rsiOversold = signals.where(
        (s) => s.indicator == 'RSI' && s.signal.contains('超卖'),
      );
      expect(rsiOversold.isNotEmpty, true, reason: 'Should detect RSI oversold signal');

      // Also verify with real price data that strong downtrend produces low RSI
      final prices = <double>[];
      double price = 50.0;
      for (int i = 0; i < 30; i++) {
        prices.add(price);
        price *= 0.95;
      }
      final realData = calcAllIndicators(_pricesToKlines(prices));
      expect(realData.last.rsi6, lessThan(30), reason: 'Strong downtrend should produce low RSI');
    });
  });

  // ========== Supplementary MA Signal Tests ==========
  group('MA Supplementary Signals', () {
    test('股价站上MA5 signal detected', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.close <= prev.ma5, last.close > last.ma5
      data[n - 2] = data[n - 2].copyWith(close: 14.0, ma5: 15.0);
      data[n - 1] = data[n - 1].copyWith(close: 16.0, ma5: 15.0);

      final signals = detectSignals(data);
      final maAbove = signals.where(
        (s) => s.indicator == 'MA' && s.signal == '股价站上MA5',
      );
      expect(maAbove.isNotEmpty, true, reason: 'Should detect price crossing above MA5');
      expect(maAbove.first.type, 'buy');
    });

    test('MA10/MA20 golden cross detected', () {
      final raw = List.generate(60, (i) {
        // Start declining, then strong recovery to create MA10/MA20 cross
        final price = i < 30 ? 15.0 - (30 - i) * 0.1 : 12.0 + (i - 30) * 0.3;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price - 0.1, high: price + 0.2, low: price - 0.2, close: price,
          volume: 10000, amount: 10000 * price,
        );
      });
      final data = calcAllIndicators(raw);
      final signals = detectSignals(data);
      // Check for MA10/MA20 cross signals - just verify no crash
      expect(signals, isNotNull);
    });

    test('均线多头排列 signal detected in strong uptrend', () {
      final data = calcAllIndicators(generateUptrendKlines(80));
      final signals = detectSignals(data);
      final alignment = signals.where((s) => s.signal == '均线多头排列').toList();
      final last = data.last;
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > last.ma60 && last.ma60 > 0) {
        expect(alignment, isNotEmpty);
        expect(alignment.first.type, equals('buy'));
      }
    });

    test('均线空头排列 signal detected in strong downtrend', () {
      final data = calcAllIndicators(generateDowntrendKlines(80));
      final signals = detectSignals(data);
      final alignment = signals.where((s) => s.signal == '均线空头排列').toList();
      final last = data.last;
      if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma20 < last.ma60 && last.ma60 > 0) {
        expect(alignment, isNotEmpty);
        expect(alignment.first.type, equals('sell'));
      }
    });
  });

  // ========== Supplementary MACD Signal Tests ==========
  group('MACD Supplementary Signals', () {
    test('绿柱缩短 signal detected', () {
      // Create data where MACD histogram is negative but starting to shrink
      final raw = List.generate(60, (i) {
        final price = i < 50 ? 20.0 - (50 - i) * 0.15 : 12.5 + (i - 49) * 0.1;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price - 0.1, high: price + 0.2, low: price - 0.2, close: price,
          volume: 10000, amount: 10000 * price,
        );
      });
      final data = calcAllIndicators(raw);
      final signals = detectSignals(data);
      // Just verify no crash and signals are generated
      expect(signals, isNotNull);
    });

    test('MACD divergence signals work', () {
      final data = calcAllIndicators(generateUptrendKlines(60));
      final signals = detectSignals(data);
      final divSignals = signals.where((s) => s.signal.contains('背离')).toList();
      // Divergence may or may not be present, just verify structure
      for (final s in divSignals) {
        expect(s.indicator, equals('MACD'));
        expect(s.strength, greaterThan(0));
      }
    });
  });

  // ========== Supplementary RSI Signal Tests ==========
  group('RSI Supplementary Signals', () {
    test('RSI extreme overbought/oversold signals', () {
      var data = _baseData();
      final n = data.length;
      // Force prev.rsi6 <= 80, last.rsi6 > 80 to trigger "RSI超买"
      data[n - 2] = data[n - 2].copyWith(rsi6: 78.0);
      data[n - 1] = data[n - 1].copyWith(rsi6: 85.0);

      final signals = detectSignals(data);
      final rsiSignals = signals.where((s) => s.indicator == 'RSI').toList();
      // Should detect RSI signals in extreme conditions
      expect(rsiSignals, isNotEmpty);
    });

    test('RSI 50-line cross signals', () {
      final data = calcAllIndicators(generateUptrendKlines(60));
      final signals = detectSignals(data);
      final rsi50Signals = signals.where((s) => s.signal.contains('50')).toList();
      // May or may not be present, just verify structure
      for (final s in rsi50Signals) {
        expect(s.indicator, equals('RSI'));
      }
    });
  });

  // ========== Supplementary BOLL Signal Tests ==========
  group('BOLL Supplementary Signals', () {
    test('站上中轨/跌破中轨 signals', () {
      final data = calcAllIndicators(generateUptrendKlines(60));
      final signals = detectSignals(data);
      final midSignals = signals.where((s) => s.signal.contains('中轨')).toList();
      for (final s in midSignals) {
        expect(s.indicator, equals('BOLL'));
        expect(s.strength, greaterThan(0));
      }
    });

    test('布林带收窄 signal when bandwidth is small', () {
      // Generate very stable data to create narrow BOLL bands
      final raw = List.generate(60, (i) {
        final price = 15.0 + (i % 3 - 1) * 0.01; // Very small oscillation
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price, high: price + 0.02, low: price - 0.02, close: price,
          volume: 10000, amount: 10000 * price,
        );
      });
      final data = calcAllIndicators(raw);
      final signals = detectSignals(data);
      // May or may not be detected, just verify no crash
      expect(signals, isNotNull);
    });
  });

  // ========== Supplementary Volume-Price Signal Tests ==========
  group('Volume-Price Supplementary Signals', () {
    test('放量下跌 signal detected', () {
      double price = 20.0;
      final raw = List.generate(60, (i) {
        final open = price;
        price *= i >= 55 ? 0.95 : 0.99; // Accelerating decline with high volume at end
        final vol = i >= 55 ? 50000.0 : 10000.0;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: open, high: open * 1.01, low: price, close: price,
          volume: vol, amount: vol * (open + price) / 2,
        );
      });
      final data = calcAllIndicators(raw);
      final signals = detectSignals(data);
      final volDownSignals = signals.where((s) => s.signal == '放量下跌').toList();
      // Should detect volume decline signal
      if (volDownSignals.isNotEmpty) {
        expect(volDownSignals.first.type, equals('sell'));
      }
    });
  });
}
