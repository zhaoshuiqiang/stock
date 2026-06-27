import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/analysis/limit_up_universe_provider.dart';
import 'package:stock_analyzer/analysis/sentiment_thermometer.dart';

void main() {
  group('P0 E2E', () {
    test('full pipeline: stocks → analyzer → sentiment', () {
      // 1. 模拟涨停池数据
      final todayStocks = [
        LimitUpStock(
            code: '600519',
            name: '茅台',
            consecutiveDays: 3,
            sealAmount: 23000,
            firstLimitTime: DateTime(2026, 6, 27, 9, 25),
            isZhaBan: false,
            sector: '白酒',
            price: 1689.5,
            changePct: 10.0),
        LimitUpStock(
            code: '000001',
            name: '平安银行',
            consecutiveDays: 1,
            sealAmount: 5000,
            firstLimitTime: DateTime(2026, 6, 27, 10, 30),
            isZhaBan: false,
            sector: '银行',
            price: 12.5,
            changePct: 10.0),
      ];

      // 2. analyzeBatchList
      final analyses = LimitUpAnalyzer.analyzeBatchList(todayStocks);
      expect(analyses, hasLength(2));

      // 3. SentimentThermometer.compute
      final sentiment = SentimentThermometer.compute(
        todayPool: analyses,
        yesterdayPool: [],
        todayQuotePct: {},
      );
      expect(sentiment.temperature, greaterThan(0));
      expect(sentiment.phase, isNotNull);
      expect(sentiment.limitUpCount, 2);

      // 4. 验证 LimitUpAnalysis.toMap 可序列化
      for (final a in analyses) {
        final m = a.toMap();
        expect(m['code'], isNotNull);
        expect(m['consecutive_days'], isNotNull);
      }
    });

    test('fallback: empty pool does not crash', () {
      final sentiment = SentimentThermometer.compute(
        todayPool: [],
        yesterdayPool: [],
        todayQuotePct: {},
      );
      expect(sentiment.temperature, lessThan(50)); // 空池温度低
    });

    test('mergeAndDedup deduplicates by code', () {
      final today = [LimitUpStock(code: '001', name: 'A')];
      final fresh = [
        LimitUpStock(code: '001', name: 'A2'),
        LimitUpStock(code: '002', name: 'B')
      ];
      final merged = LimitUpUniverseProvider.mergeAndDedup(today, fresh);
      expect(merged, hasLength(2));
      expect(merged.firstWhere((s) => s.code == '001').name, 'A2');
    });
  });
}
