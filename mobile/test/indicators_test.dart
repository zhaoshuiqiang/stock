import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';

// ---- Helper functions ----

List<HistoryKline> generateKlines(List<double> prices) {
  return List.generate(prices.length, (i) {
    final price = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: 10000,
      amount: 10000 * price,
      change: i > 0 ? price - prices[i - 1] : 0,
      changePct: i > 0 && prices[i - 1] > 0
          ? (price - prices[i - 1]) / prices[i - 1] * 100
          : 0,
    );
  });
}

List<HistoryKline> generateUptrendKlines(int count,
    {double startPrice = 10.0, double dailyReturn = 0.02}) {
  double price = startPrice;
  return List.generate(count, (i) {
    final open = price;
    price *= (1 + dailyReturn);
    final close = price;
    final k = HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: close * 1.01,
      low: open * 0.99,
      close: close,
      volume: 10000 + i * 100,
      amount: 10000 * (open + close) / 2,
      change: close - open,
      changePct: (close - open) / open * 100,
    );
    price = close;
    return k;
  });
}

List<HistoryKline> generateDowntrendKlines(int count,
    {double startPrice = 10.0, double dailyReturn = -0.02}) {
  return generateUptrendKlines(count,
      startPrice: startPrice, dailyReturn: dailyReturn.abs() * -1);
}

void main() {
  // ============================================================
  // 1. MA (Moving Average) Tests
  // ============================================================
  group('MA (Moving Average)', () {
    test('MA5 calculation with known data', () {
      final data = generateKlines([10, 11, 12, 13, 14, 15, 16]);
      final result = calcMA(data, [5]);

      // MA5 at index 4 (5th element): avg(10,11,12,13,14) = 12
      expect(result[4].ma5, closeTo(12.0, 0.01));
      // MA5 at index 5: avg(11,12,13,14,15) = 13
      expect(result[5].ma5, closeTo(13.0, 0.01));
      // MA5 at index 6: avg(12,13,14,15,16) = 14
      expect(result[6].ma5, closeTo(14.0, 0.01));
    });

    test('MA10 calculation with known data', () {
      final prices = List.generate(15, (i) => 10.0 + i);
      final data = generateKlines(prices);
      final result = calcMA(data, [10]);

      // MA10 at index 9: avg(10..19) = 14.5
      expect(result[9].ma10, closeTo(14.5, 0.01));
      // MA10 at index 14: avg(15..24) = 19.5
      expect(result[14].ma10, closeTo(19.5, 0.01));
    });

    test('MA20 calculation with known data', () {
      final prices = List.generate(25, (i) => 10.0 + i);
      final data = generateKlines(prices);
      final result = calcMA(data, [20]);

      // MA20 at index 19: avg(10..29) = 19.5
      expect(result[19].ma20, closeTo(19.5, 0.01));
      // Before 20 data points, MA20 should be 0
      expect(result[18].ma20, 0);
    });

    test('MA60 calculation with known data', () {
      final prices = List.generate(65, (i) => 10.0 + i);
      final data = generateKlines(prices);
      final result = calcMA(data, [60]);

      // MA60 at index 59: avg(10..69) = 39.5
      expect(result[59].ma60, closeTo(39.5, 0.01));
      // Before 60 data points, MA60 should be 0
      expect(result[58].ma60, 0);
    });

    test('insufficient data points returns 0', () {
      final data = generateKlines([10, 11, 12]);
      final result = calcMA(data, [5]);

      // Only 3 data points, MA5 requires 5, so all should be 0
      for (final k in result) {
        expect(k.ma5, 0);
      }
    });

    test('constant prices: MA should equal that price', () {
      final data = generateKlines(List.filled(20, 15.0));
      final result = calcMA(data, [5, 10, 20]);

      // All MAs should equal the constant price
      expect(result[4].ma5, closeTo(15.0, 0.001));
      expect(result[9].ma10, closeTo(15.0, 0.001));
      expect(result[19].ma20, closeTo(15.0, 0.001));
    });

    test('empty data returns empty list', () {
      final result = calcMA([], [5]);
      expect(result, isEmpty);
    });

    test('multi-period MA simultaneously', () {
      final prices = List.generate(30, (i) => 10.0 + i);
      final data = generateKlines(prices);
      final result = calcMA(data, [5, 10, 20]);

      expect(result[4].ma5, greaterThan(0));
      expect(result[9].ma10, greaterThan(0));
      expect(result[19].ma20, greaterThan(0));
      // MA10 not available at index 4
      expect(result[4].ma10, 0);
    });
  });

  // ============================================================
  // 2. MACD Tests
  // ============================================================
  group('MACD', () {
    test('DIF, DEA, Histogram calculation', () {
      final closes = <double>[];
      for (int i = 0; i < 15; i++) {
        closes.add(10.0 + i * 0.5);
      }
      for (int i = 0; i < 15; i++) {
        closes.add(17.0 - i * 0.5);
      }
      final data = generateKlines(closes);
      final result = calcMACD(data);

      final last = result.last;
      expect(last.macdDif, isNot(0));
      expect(last.macdDea, isNot(0));
      expect(last.macdHist, isNot(0));
      // Histogram = 2 * (DIF - DEA)
      expect(last.macdHist, closeTo(2 * (last.macdDif - last.macdDea), 0.001));
    });

    test('uptrend: DIF should be positive', () {
      final data = generateUptrendKlines(40, startPrice: 10.0, dailyReturn: 0.03);
      final result = calcMACD(data);

      expect(result.last.macdDif, greaterThan(0));
    });

    test('flat data: MACD values should be near 0', () {
      final data = generateKlines(List.filled(40, 20.0));
      final result = calcMACD(data);

      final last = result.last;
      expect(last.macdDif, closeTo(0, 0.001));
      expect(last.macdDea, closeTo(0, 0.001));
      expect(last.macdHist, closeTo(0, 0.001));
    });

    test('downtrend: DIF should be negative', () {
      final data = generateDowntrendKlines(40, startPrice: 50.0, dailyReturn: -0.03);
      final result = calcMACD(data);

      expect(result.last.macdDif, lessThan(0));
    });

    test('empty data returns empty list', () {
      final result = calcMACD([]);
      expect(result, isEmpty);
    });
  });

  // ============================================================
  // 3. RSI Tests
  // ============================================================
  group('RSI', () {
    test('RSI6 calculation with known data', () {
      final data = generateUptrendKlines(30, startPrice: 10.0, dailyReturn: 0.02);
      final result = calcRSI(data, [6]);

      // In uptrend, RSI6 should be high
      expect(result.last.rsi6, greaterThan(70));
    });

    test('RSI12 calculation', () {
      final data = generateUptrendKlines(30, startPrice: 10.0, dailyReturn: 0.02);
      final result = calcRSI(data, [12]);

      expect(result.last.rsi12, greaterThan(50));
    });

    test('RSI24 calculation', () {
      final data = generateUptrendKlines(40, startPrice: 10.0, dailyReturn: 0.02);
      final result = calcRSI(data, [24]);

      expect(result.last.rsi24, greaterThan(50));
    });

    test('continuously rising prices: RSI should be near 100', () {
      final data = generateUptrendKlines(30, startPrice: 10.0, dailyReturn: 0.05);
      final result = calcRSI(data, [6]);

      expect(result.last.rsi6, greaterThan(90));
    });

    test('continuously falling prices: RSI should be near 0', () {
      final data = generateDowntrendKlines(30, startPrice: 50.0, dailyReturn: -0.05);
      final result = calcRSI(data, [6]);

      expect(result.last.rsi6, lessThan(10));
    });

    test('mixed prices: RSI should be around 50', () {
      // Alternating up and down prices
      final prices = <double>[];
      double price = 10.0;
      for (int i = 0; i < 40; i++) {
        prices.add(price);
        price += (i % 2 == 0) ? 0.5 : -0.5;
      }
      final data = generateKlines(prices);
      final result = calcRSI(data, [6]);

      // RSI should be in the middle range
      expect(result.last.rsi6, greaterThan(30));
      expect(result.last.rsi6, lessThan(70));
    });

    test('RSI always in range [0, 100]', () {
      final closes = <double>[];
      for (int i = 0; i < 30; i++) {
        closes.add(10.0 + (i % 5) * 0.8 - (i % 3) * 0.3);
      }
      final data = generateKlines(closes);
      final result = calcRSI(data, [6, 12, 24]);

      for (int i = 6; i < result.length; i++) {
        expect(result[i].rsi6, greaterThanOrEqualTo(0));
        expect(result[i].rsi6, lessThanOrEqualTo(100));
      }
      for (int i = 12; i < result.length; i++) {
        expect(result[i].rsi12, greaterThanOrEqualTo(0));
        expect(result[i].rsi12, lessThanOrEqualTo(100));
      }
    });
  });

  // ============================================================
  // 4. KDJ Tests
  // ============================================================
  group('KDJ', () {
    test('K, D, J calculation', () {
      final closes = <double>[];
      for (int i = 0; i < 20; i++) {
        closes.add(10.0 + (i % 5) * 0.5);
      }
      final data = generateKlines(closes);
      final result = calcKDJ(data);

      final last = result.last;
      expect(last.k, greaterThan(0));
      expect(last.d, greaterThan(0));
      // J = 3K - 2D
      expect(last.j, closeTo(3 * last.k - 2 * last.d, 0.01));
    });

    test('golden cross: K crosses above D', () {
      // Create data that transitions from downtrend to uptrend
      final prices = <double>[];
      double price = 50.0;
      // First: falling
      for (int i = 0; i < 15; i++) {
        prices.add(price);
        price -= 1.0;
      }
      // Then: rising
      for (int i = 0; i < 15; i++) {
        prices.add(price);
        price += 1.5;
      }
      final data = generateKlines(prices);
      final result = calcKDJ(data);

      // Check that at some point K > D (golden cross occurred)
      bool goldenCrossFound = false;
      for (int i = 1; i < result.length; i++) {
        if (result[i].k > result[i].d && result[i - 1].k <= result[i - 1].d) {
          goldenCrossFound = true;
          break;
        }
      }
      expect(goldenCrossFound, isTrue);
    });

    test('death cross: K crosses below D', () {
      // Create data that transitions from uptrend to downtrend
      final prices = <double>[];
      double price = 10.0;
      // First: rising
      for (int i = 0; i < 15; i++) {
        prices.add(price);
        price += 1.5;
      }
      // Then: falling
      for (int i = 0; i < 15; i++) {
        prices.add(price);
        price -= 1.0;
      }
      final data = generateKlines(prices);
      final result = calcKDJ(data);

      // Check that at some point K < D (death cross occurred)
      bool deathCrossFound = false;
      for (int i = 1; i < result.length; i++) {
        if (result[i].k < result[i].d && result[i - 1].k >= result[i - 1].d) {
          deathCrossFound = true;
          break;
        }
      }
      expect(deathCrossFound, isTrue);
    });

    test('J value can exceed 100 or go below 0', () {
      // Strong uptrend should push J above 100
      final upData = generateUptrendKlines(20, startPrice: 10.0, dailyReturn: 0.05);
      final upResult = calcKDJ(upData);

      bool jAbove100 = upResult.any((k) => k.j > 100);
      expect(jAbove100, isTrue, reason: 'J should exceed 100 in strong uptrend');

      // Strong downtrend should push J below 0
      final downData =
          generateDowntrendKlines(20, startPrice: 50.0, dailyReturn: -0.05);
      final downResult = calcKDJ(downData);

      bool jBelow0 = downResult.any((k) => k.j < 0);
      expect(jBelow0, isTrue, reason: 'J should go below 0 in strong downtrend');
    });

    test('insufficient data returns original list', () {
      final data = generateKlines([10, 11, 12]);
      final result = calcKDJ(data);
      expect(result.length, 3);
      // KDJ values should remain 0 since we need at least 9 data points
      for (final k in result) {
        expect(k.k, 0);
        expect(k.d, 0);
        expect(k.j, 0);
      }
    });
  });

  // ============================================================
  // 5. BOLL Tests
  // ============================================================
  group('BOLL', () {
    test('upper > mid > lower', () {
      final closes = List.generate(30, (i) => 10.0 + (i % 7) * 0.3);
      final data = generateKlines(closes);
      final result = calcBOLL(data);

      final last = result.last;
      expect(last.bollUpper, greaterThan(last.bollMid));
      expect(last.bollMid, greaterThan(last.bollLower));
    });

    test('mid band equals MA20', () {
      final closes = List.generate(30, (i) => 10.0 + i * 0.2);
      final data = generateKlines(closes);
      final bollResult = calcBOLL(data);
      final maResult = calcMA(data, [20]);

      expect(bollResult.last.bollMid, closeTo(maResult.last.ma20, 0.01));
    });

    test('band width increases with volatility', () {
      // Low volatility data
      final lowVolPrices = List.generate(25, (i) => 10.0 + (i % 3) * 0.1);
      final lowVolData = generateKlines(lowVolPrices);
      final lowVolResult = calcBOLL(lowVolData);

      // High volatility data
      final highVolPrices = List.generate(25, (i) => 10.0 + (i % 3) * 2.0);
      final highVolData = generateKlines(highVolPrices);
      final highVolResult = calcBOLL(highVolData);

      final lowVolWidth =
          lowVolResult.last.bollUpper - lowVolResult.last.bollLower;
      final highVolWidth =
          highVolResult.last.bollUpper - highVolResult.last.bollLower;

      expect(highVolWidth, greaterThan(lowVolWidth),
          reason: 'High volatility should produce wider BOLL bands');
    });

    test('constant prices: upper and lower equal mid', () {
      final data = generateKlines(List.filled(25, 15.0));
      final result = calcBOLL(data);

      final last = result.last;
      expect(last.bollUpper, closeTo(last.bollMid, 0.001));
      expect(last.bollLower, closeTo(last.bollMid, 0.001));
    });

    test('insufficient data: BOLL values should be 0', () {
      final data = generateKlines(List.generate(10, (i) => 10.0 + i));
      final result = calcBOLL(data);

      expect(result.last.bollUpper, 0);
      expect(result.last.bollMid, 0);
      expect(result.last.bollLower, 0);
    });
  });

  // ============================================================
  // 6. calcAllIndicators Integration Test
  // ============================================================
  group('calcAllIndicators', () {
    test('populates all indicator fields with realistic data', () {
      // Generate 80 data points with realistic price movements
      final prices = <double>[];
      double price = 10.0;
      for (int i = 0; i < 80; i++) {
        prices.add(price);
        // Simulate realistic price movement with some volatility
        price += (i % 10 - 4) * 0.3;
        if (price < 1) price = 1;
      }
      final data = generateKlines(prices);
      final result = calcAllIndicators(data);

      final last = result.last;

      // MA fields
      expect(last.ma5, isNot(0));
      expect(last.ma10, isNot(0));
      expect(last.ma20, isNot(0));
      expect(last.ma60, isNot(0));

      // MACD fields
      expect(last.macdDif, isNot(0));
      expect(last.macdDea, isNot(0));
      expect(last.macdHist, isNot(0));

      // RSI fields
      expect(last.rsi6, isNot(0));
      expect(last.rsi12, isNot(0));
      expect(last.rsi24, isNot(0));

      // KDJ fields
      expect(last.k, isNot(0));
      expect(last.d, isNot(0));

      // BOLL fields
      expect(last.bollUpper, isNot(0));
      expect(last.bollMid, isNot(0));
      expect(last.bollLower, isNot(0));

      // Volume MA fields
      expect(last.volMa5, isNot(0));
      expect(last.volMa10, isNot(0));
    });

    test('works with at least 60 data points', () {
      final data = generateUptrendKlines(65, startPrice: 10.0, dailyReturn: 0.01);
      final result = calcAllIndicators(data);

      expect(result.length, 65);
      final last = result.last;

      // All major indicators should be populated with 65 data points
      expect(last.ma5, greaterThan(0));
      expect(last.ma10, greaterThan(0));
      expect(last.ma20, greaterThan(0));
      expect(last.ma60, greaterThan(0));
      expect(last.bollUpper, greaterThan(0));
      expect(last.rsi6, greaterThan(0));
      expect(last.k, greaterThan(0));
    });

    test('empty data returns empty list', () {
      final result = calcAllIndicators([]);
      expect(result, isEmpty);
    });

    test('single data point returns original list', () {
      final data = generateKlines([10.0]);
      final result = calcAllIndicators(data);
      expect(result.length, 1);
    });
  });

  // ============================================================
  // 7. getIndicatorSummary Tests
  // ============================================================
  group('getIndicatorSummary', () {
    test('returns non-empty summary', () {
      final closes = List.generate(80, (i) => 10.0 + (i % 10) * 0.5);
      final data = calcAllIndicators(generateKlines(closes));
      final summary = getIndicatorSummary(data);
      expect(summary, isNotEmpty);
      expect(summary.containsKey('DIF'), isTrue);
    });

    test('empty data returns empty map', () {
      final summary = getIndicatorSummary([]);
      expect(summary, isEmpty);
    });
  });

  // ============================================================
  // 8. QuoteData fromJson edge cases
  // ============================================================
  group('QuoteData fromJson edge cases', () {
    test('handles various numeric types', () {
      final json = {
        'code': 'TEST',
        'price': '10.5',
        'change': 3,
        'change_pct': 1.5,
        'pe': null,
        'pb': 'abc',
      };
      final quote = QuoteData.fromJson(json);
      expect(quote.price, 10.5);
      expect(quote.change, 3.0);
      expect(quote.pe, 0);
      expect(quote.pb, 0);
    });
  });
}
