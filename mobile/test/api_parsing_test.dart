import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('Tencent Quote Parsing', () {
    test('QuoteData.fromJson parses all fields correctly', () {
      final json = {
        'code': 'sh600519',
        'name': '贵州茅台',
        'price': 1800.50,
        'change': 25.30,
        'change_pct': 1.42,
        'open': 1780.00,
        'high': 1810.00,
        'low': 1775.00,
        'pre_close': 1775.20,
        'volume': 35000.0,
        'amount': 6300000000.0,
        'amplitude': 1.97,
        'turnover': 0.85,
        'pe': 35.2,
        'pb': 12.5,
        'total_market_cap': 2260000000000.0,
        'circulating_market_cap': 2260000000000.0,
        'main_inflow': 500000000.0,
        'main_outflow': 450000000.0,
        'main_net_flow': 50000000.0,
        'main_net_flow_rate': 0.79,
      };
      final quote = QuoteData.fromJson(json);
      expect(quote.code, equals('sh600519'));
      expect(quote.name, equals('贵州茅台'));
      expect(quote.price, closeTo(1800.50, 0.01));
      expect(quote.change, closeTo(25.30, 0.01));
      expect(quote.changePct, closeTo(1.42, 0.01));
      expect(quote.open, closeTo(1780.00, 0.01));
      expect(quote.high, closeTo(1810.00, 0.01));
      expect(quote.low, closeTo(1775.00, 0.01));
      expect(quote.preClose, closeTo(1775.20, 0.01));
      expect(quote.volume, closeTo(35000.0, 0.01));
      expect(quote.amount, closeTo(6300000000.0, 0.01));
      expect(quote.amplitude, closeTo(1.97, 0.01));
      expect(quote.turnover, closeTo(0.85, 0.01));
      expect(quote.pe, closeTo(35.2, 0.01));
      expect(quote.pb, closeTo(12.5, 0.01));
      expect(quote.totalMarketCap, closeTo(2260000000000.0, 0.01));
      expect(quote.circulatingMarketCap, closeTo(2260000000000.0, 0.01));
      expect(quote.mainInflow, closeTo(500000000.0, 0.01));
      expect(quote.mainOutflow, closeTo(450000000.0, 0.01));
      expect(quote.mainNetFlow, closeTo(50000000.0, 0.01));
      expect(quote.mainNetFlowRate, closeTo(0.79, 0.01));
    });

    test('QuoteData.fromJson handles integer values', () {
      final json = {
        'code': 'sz000001',
        'price': 15,  // int instead of double
        'volume': 100000,  // int
      };
      final quote = QuoteData.fromJson(json);
      expect(quote.price, equals(15.0));
      expect(quote.volume, equals(100000.0));
    });

    test('QuoteData.fromJson handles string values', () {
      final json = {
        'code': 'sh600519',
        'price': '1800.50',
        'change_pct': '1.42',
      };
      final quote = QuoteData.fromJson(json);
      expect(quote.price, closeTo(1800.50, 0.01));
      expect(quote.changePct, closeTo(1.42, 0.01));
    });

    test('QuoteData.fromJson handles null and missing values', () {
      final json = <String, dynamic>{'code': 'sh600519'};
      final quote = QuoteData.fromJson(json);
      expect(quote.code, equals('sh600519'));
      expect(quote.price, equals(0));
      expect(quote.name, equals(''));
    });

    test('QuoteData.fromJson handles invalid string values', () {
      final json = {
        'code': 'sh600519',
        'price': 'invalid',
      };
      final quote = QuoteData.fromJson(json);
      expect(quote.price, equals(0));
    });

    test('QuoteData confidence field defaults to high', () {
      final json = {'code': 'sh600519'};
      final quote = QuoteData.fromJson(json);
      expect(quote.confidence, equals('high'));
    });

    test('QuoteData confidence field from json', () {
      final json = {'code': 'sh600519', 'confidence': 'low'};
      final quote = QuoteData.fromJson(json);
      expect(quote.confidence, equals('low'));
    });
  });

  group('Kline Data Parsing', () {
    test('HistoryKline.fromJson parses date correctly', () {
      final json = {
        'date': '2024-01-15',
        'open': 10.5,
        'high': 11.0,
        'low': 10.2,
        'close': 10.8,
        'volume': 50000.0,
        'amount': 540000.0,
      };
      final kline = HistoryKline.fromJson(json);
      expect(kline.date.year, equals(2024));
      expect(kline.date.month, equals(1));
      expect(kline.date.day, equals(15));
      expect(kline.open, closeTo(10.5, 0.01));
      expect(kline.high, closeTo(11.0, 0.01));
      expect(kline.low, closeTo(10.2, 0.01));
      expect(kline.close, closeTo(10.8, 0.01));
      expect(kline.volume, closeTo(50000.0, 0.01));
    });

    test('HistoryKline new indicator fields default to 0', () {
      final json = {
        'date': '2024-01-15',
        'open': 10.5,
        'close': 10.8,
      };
      final kline = HistoryKline.fromJson(json);
      expect(kline.ema5, equals(0));
      expect(kline.atr14, equals(0));
      expect(kline.obv, equals(0));
      expect(kline.bias6, equals(0));
      expect(kline.plusDi14, equals(0));
      expect(kline.adx14, equals(0));
    });
  });

  group('MarketSentiment Parsing', () {
    test('MarketSentiment.fromJson parses correctly', () {
      final json = {
        'up_count': 2500,
        'down_count': 1800,
        'flat_count': 200,
        'limit_up_count': 50,
        'limit_down_count': 10,
        'avg_change_pct': 0.35,
      };
      final sentiment = MarketSentiment.fromJson(json);
      expect(sentiment.upCount, equals(2500));
      expect(sentiment.downCount, equals(1800));
      expect(sentiment.flatCount, equals(200));
      expect(sentiment.total, equals(4500));
      expect(sentiment.upRatio, closeTo(2500 / 4500, 0.001));
    });

    test('MarketSentiment with zero total', () {
      final json = <String, dynamic>{};
      final sentiment = MarketSentiment.fromJson(json);
      expect(sentiment.total, equals(0));
      expect(sentiment.upRatio, equals(0));
    });
  });

  group('ArchiveRecord Serialization', () {
    test('ArchiveRecord toMap/fromMap round-trip', () {
      final record = ArchiveRecord(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800.50,
        changePct: 1.42,
        score: 75,
        recommendation: '买入',
        riskLevel: '中等',
        buySignalCount: 3,
        sellSignalCount: 1,
        activeStrategyCount: 2,
        confluenceScore: 5,
        topSignals: 'MACD金叉,放量上涨',
        archivedAt: DateTime(2024, 6, 15, 10, 30),
      );
      final map = record.toMap();
      final restored = ArchiveRecord.fromMap(map);
      expect(restored.code, equals(record.code));
      expect(restored.name, equals(record.name));
      expect(restored.price, closeTo(record.price, 0.01));
      expect(restored.changePct, closeTo(record.changePct, 0.01));
      expect(restored.score, equals(record.score));
      expect(restored.recommendation, equals(record.recommendation));
      expect(restored.riskLevel, equals(record.riskLevel));
      expect(restored.buySignalCount, equals(record.buySignalCount));
      expect(restored.sellSignalCount, equals(record.sellSignalCount));
      expect(restored.activeStrategyCount, equals(record.activeStrategyCount));
      expect(restored.confluenceScore, equals(record.confluenceScore));
      expect(restored.topSignals, equals(record.topSignals));
    });
  });

  group('SectorInfo Model', () {
    test('SectorInfo has correct defaults', () {
      final sector = SectorInfo(name: '白酒', code: 'BK0477');
      expect(sector.name, equals('白酒'));
      expect(sector.code, equals('BK0477'));
      expect(sector.changePct, equals(0));
      expect(sector.leadStockName, equals(''));
      expect(sector.stockCount, equals(0));
    });
  });
}
