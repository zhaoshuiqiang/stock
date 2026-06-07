import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';

List<HistoryKline> _makeKlines(List<double> closes, {List<double>? volumes}) {
  final result = <HistoryKline>[];
  for (int i = 0; i < closes.length; i++) {
    final c = closes[i];
    final o = i > 0 ? closes[i - 1] : c;
    final h = c > o ? c : o;
    final l = c < o ? c : o;
    result.add(HistoryKline(
      date: DateTime(2026, 1, 1).add(Duration(days: i)),
      open: o,
      high: h + 0.5,
      low: l - 0.5,
      close: c,
      volume: volumes != null && i < volumes.length ? volumes[i] : 1000.0,
    ));
  }
  return result;
}

void main() {
  group('calcMA', () {
    test('MA5 correct', () {
      final data = _makeKlines([10, 11, 12, 13, 14, 15, 16]);
      final result = calcMA(data, [5]);
      expect(result[3].ma5, 0);
      expect(result[4].ma5, closeTo(12.0, 0.01));
      expect(result[5].ma5, closeTo(13.0, 0.01));
      expect(result[6].ma5, closeTo(14.0, 0.01));
    });

    test('multi-period MA', () {
      final closes = List.generate(30, (i) => 10.0 + i);
      final data = _makeKlines(closes);
      final result = calcMA(data, [5, 10, 20]);
      expect(result[4].ma5, greaterThan(0));
      expect(result[9].ma10, greaterThan(0));
      expect(result[19].ma20, greaterThan(0));
      expect(result[4].ma10, 0);
    });

    test('empty data', () {
      final result = calcMA([], [5]);
      expect(result, isEmpty);
    });
  });

  group('calcMACD', () {
    test('basic MACD', () {
      final closes = <double>[];
      for (int i = 0; i < 15; i++) closes.add(10.0 + i * 0.5);
      for (int i = 0; i < 15; i++) closes.add(17.0 - i * 0.5);
      final data = _makeKlines(closes);
      final result = calcMACD(data);

      expect(result.last.macdDif, isNot(0));
      expect(result.last.macdDea, isNot(0));
      expect(result.last.macdHist, isNot(0));
      expect(
        result.last.macdHist,
        closeTo(2 * (result.last.macdDif - result.last.macdDea), 0.001),
      );
    });

    test('uptrend DIF positive', () {
      final closes = List.generate(40, (i) => 10.0 + i * 0.3);
      final data = _makeKlines(closes);
      final result = calcMACD(data);
      expect(result.last.macdDif, greaterThan(0));
    });

    test('empty data', () {
      final result = calcMACD([]);
      expect(result, isEmpty);
    });
  });

  group('calcRSI', () {
    test('RSI in 0-100', () {
      final closes = <double>[];
      for (int i = 0; i < 30; i++) {
        closes.add(10.0 + (i % 5) * 0.8 - (i % 3) * 0.3);
      }
      final data = _makeKlines(closes);
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

    test('strong uptrend RSI near 100', () {
      final closes = List.generate(30, (i) => 10.0 + i);
      final data = _makeKlines(closes);
      final result = calcRSI(data, [6]);
      expect(result.last.rsi6, greaterThan(90));
    });

    test('strong downtrend RSI near 0', () {
      final closes = List.generate(30, (i) => 40.0 - i);
      final data = _makeKlines(closes);
      final result = calcRSI(data, [6]);
      expect(result.last.rsi6, lessThan(10));
    });
  });

  group('calcKDJ', () {
    test('basic KDJ', () {
      final closes = <double>[];
      for (int i = 0; i < 20; i++) {
        closes.add(10.0 + (i % 5) * 0.5);
      }
      final data = _makeKlines(closes);
      final result = calcKDJ(data);

      expect(result.last.k, greaterThan(0));
      expect(result.last.d, greaterThan(0));
      expect(result.last.j, closeTo(3 * result.last.k - 2 * result.last.d, 0.01));
    });

    test('insufficient data', () {
      final data = _makeKlines([10, 11, 12]);
      final result = calcKDJ(data);
      expect(result.length, 3);
    });
  });

  group('calcBOLL', () {
    test('upper > mid > lower', () {
      final closes = List.generate(30, (i) => 10.0 + (i % 7) * 0.3);
      final data = _makeKlines(closes);
      final result = calcBOLL(data);

      final last = result.last;
      expect(last.bollUpper, greaterThan(last.bollMid));
      expect(last.bollMid, greaterThan(last.bollLower));
    });

    test('mid equals MA20', () {
      final closes = List.generate(30, (i) => 10.0 + i * 0.2);
      final data = _makeKlines(closes);
      final bollResult = calcBOLL(data);
      final maResult = calcMA(data, [20]);

      expect(bollResult.last.bollMid, closeTo(maResult.last.ma20, 0.01));
    });

    test('insufficient data', () {
      final data = _makeKlines(List.generate(10, (i) => 10.0 + i));
      final result = calcBOLL(data);
      expect(result.last.bollUpper, 0);
    });
  });

  group('calcAllIndicators', () {
    test('all indicators populated', () {
      final closes = List.generate(80, (i) => 10.0 + (i % 10) * 0.5 - (i % 7) * 0.2);
      final data = _makeKlines(closes);
      final result = calcAllIndicators(data);

      final last = result.last;
      expect(last.ma5, isNot(0));
      expect(last.ma10, isNot(0));
      expect(last.ma20, isNot(0));
      expect(last.ma60, isNot(0));
      expect(last.macdDif, isNot(0));
      expect(last.rsi6, isNot(0));
      expect(last.k, isNot(0));
      expect(last.bollUpper, isNot(0));
      expect(last.volMa5, isNot(0));
    });
  });

  group('getIndicatorSummary', () {
    test('returns non-empty summary', () {
      final closes = List.generate(80, (i) => 10.0 + (i % 10) * 0.5);
      final data = calcAllIndicators(_makeKlines(closes));
      final summary = getIndicatorSummary(data);
      expect(summary, isNotEmpty);
      expect(summary.containsKey('DIF'), true);
    });

    test('empty data returns empty map', () {
      final summary = getIndicatorSummary([]);
      expect(summary, isEmpty);
    });
  });

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
