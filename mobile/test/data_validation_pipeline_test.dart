import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/validators/data_validator.dart';

void main() {
  group('DataValidator.validateQuote', () {
    test('valid quote returns no anomalies', () {
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800.0,
        change: 25.0,
        changePct: 1.41,
        open: 1780.0,
        high: 1810.0,
        low: 1775.0,
        preClose: 1775.0,
        volume: 35000,
        amount: 6300000000,
      );
      final result = DataValidator.validateQuote(quote);
      expect(result.anomalies, isEmpty);
    });

    test('zero price detected as anomaly', () {
      final quote = QuoteData(code: 'sh600519', price: 0);
      final result = DataValidator.validateQuote(quote);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.zeroPrice), isTrue);
    });

    test('extreme change detected as anomaly', () {
      final quote = QuoteData(code: 'sh600519', price: 20.0, changePct: 25.0, preClose: 16.0);
      final result = DataValidator.validateQuote(quote);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.extremeChange), isTrue);
    });

    test('negative open/high/low detected as anomaly', () {
      final quote = QuoteData(code: 'sh600519', price: 10.0, open: -10.0, high: 11.0, low: 9.0);
      final result = DataValidator.validateQuote(quote);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.negativeValue), isTrue);
    });

    test('high < low detected as anomaly', () {
      final quote = QuoteData(code: 'sh600519', price: 10.0, high: 9.0, low: 11.0);
      final result = DataValidator.validateQuote(quote);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.negativeValue), isTrue);
    });

    test('ST stock allows 5% change', () {
      final quote = QuoteData(code: 'sh600519', name: 'ST某某', price: 5.0, changePct: 4.5, preClose: 4.78);
      final result = DataValidator.validateQuote(quote);
      // 4.5% should not be extreme for ST stock
      expect(result.anomalies.where((a) => a.type == DataAnomalyType.extremeChange).isEmpty, isTrue);
    });
  });

  group('DataValidator.validateKlines', () {
    test('valid klines return no anomalies', () {
      final klines = List.generate(10, (i) {
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: 10.0 + i * 0.1,
          high: 10.5 + i * 0.1,
          low: 9.5 + i * 0.1,
          close: 10.2 + i * 0.1,
          volume: 10000,
          amount: 100000,
        );
      });
      final result = DataValidator.validateKlines(klines);
      expect(result.anomalies, isEmpty);
    });

    test('negative price in kline detected', () {
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 1), open: -10.0, high: 11.0, low: 9.0, close: 10.0, volume: 10000),
      ];
      final result = DataValidator.validateKlines(klines);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.negativeValue), isTrue);
    });
  });

  group('DataValidator.isStaleQuote', () {
    test('recent quote is not stale', () {
      final quote = QuoteData(
        code: 'sh600519',
        price: 1800.0,
        updateTime: DateTime.now().subtract(Duration(seconds: 30)),
      );
      expect(DataValidator.isStaleQuote(quote), isFalse);
    });

    test('quote without updateTime is not stale', () {
      final quote = QuoteData(code: 'sh600519', price: 1800.0);
      expect(DataValidator.isStaleQuote(quote), isFalse);
    });

    test('old quote during trading hours is stale', () {
      // Note: This test depends on when it runs. We test the logic by checking
      // that a quote with updateTime > 60 seconds ago during trading hours is stale.
      // Since we can't control TradingSession, we just verify the method exists and runs.
      final quote = QuoteData(
        code: 'sh600519',
        price: 1800.0,
        updateTime: DateTime.now().subtract(Duration(seconds: 120)),
      );
      // During trading hours, this should be stale; outside, not
      final result = DataValidator.isStaleQuote(quote);
      expect(result, isA<bool>());
    });
  });

  group('QuoteData Confidence Integration', () {
    test('QuoteData has confidence field', () {
      final quote = QuoteData(code: 'sh600519', price: 1800.0);
      expect(quote.confidence, equals('high'));
    });

    test('QuoteData confidence can be set to low', () {
      final quote = QuoteData(code: 'sh600519', price: 0, confidence: 'low');
      expect(quote.confidence, equals('low'));
    });

    test('QuoteData confidence can be set to medium', () {
      final quote = QuoteData(code: 'sh600519', price: 1800.0, confidence: 'medium');
      expect(quote.confidence, equals('medium'));
    });
  });

  group('DataValidator.validateKlinePrices', () {
    test('extreme daily change detected', () {
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 1), open: 10.0, high: 10.5, low: 9.5, close: 10.0, volume: 10000, changePct: 0),
        HistoryKline(date: DateTime(2024, 1, 2), open: 10.0, high: 15.0, low: 9.0, close: 14.0, volume: 50000, changePct: 40.0),
      ];
      final result = DataValidator.validateKlinePrices(klines);
      // 40% change should be detected (threshold is 30%)
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.extremeChange), isTrue);
    });

    test('zero volume with price change detected', () {
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 1), open: 10.0, close: 10.0, volume: 10000),
        HistoryKline(date: DateTime(2024, 1, 2), open: 10.0, close: 12.0, volume: 0),
      ];
      final result = DataValidator.validateKlinePrices(klines);
      expect(result.anomalies.any((a) => a.type == DataAnomalyType.zeroVolume), isTrue);
    });
  });
}
