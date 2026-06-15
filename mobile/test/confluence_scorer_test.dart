import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/confluence_scorer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('ConfluenceScorer', () {
    /// 创建默认中性 HistoryKline
    HistoryKline createNeutralKline() {
      return HistoryKline(
        date: DateTime.now(),
        open: 10.0,
        high: 11.0,
        low: 9.0,
        close: 10.0,
        volume: 1000,
        ma5: 10.0,
        ma10: 10.0,
        ma20: 10.0,
        volMa5: 1000,
        macdDif: 0.0,
        macdDea: 0.0,
        macdHist: 0.0,
        rsi6: 50.0,
        k: 50.0,
        d: 50.0,
        bollMid: 10.0,
      );
    }

    /// 创建多头排列 HistoryKline
    HistoryKline createBullishKline() {
      return HistoryKline(
        date: DateTime.now(),
        open: 9.0,
        high: 11.0,
        low: 9.0,
        close: 10.5,
        volume: 1500,
        ma5: 10.5,
        ma10: 10.0,
        ma20: 9.5,
        volMa5: 1000,
        macdDif: 0.5,
        macdDea: 0.2,
        macdHist: 0.3,
        rsi6: 70.0,
        k: 75.0,
        d: 60.0,
        bollMid: 10.0,
        wr14: 85.0,
        cci14: 150.0,
      );
    }

    /// 创建空头排列 HistoryKline
    HistoryKline createBearishKline() {
      return HistoryKline(
        date: DateTime.now(),
        open: 11.0,
        high: 11.0,
        low: 9.0,
        close: 9.5,
        volume: 1500,
        ma5: 9.5,
        ma10: 10.0,
        ma20: 10.5,
        volMa5: 1000,
        macdDif: -0.5,
        macdDea: -0.2,
        macdHist: -0.3,
        rsi6: 25.0,
        k: 25.0,
        d: 60.0,
        bollMid: 10.0,
        wr14: 10.0,
        cci14: -150.0,
      );
    }

    test('返回的评分在 0-10 范围内', () {
      final kline = createNeutralKline();
      final result = ConfluenceScorer.score(kline, []);

      expect(result.score, greaterThanOrEqualTo(0.0));
      expect(result.score, lessThanOrEqualTo(10.0));
    });

    test('多头排列产生比空头排列更高的评分', () {
      final bullResult = ConfluenceScorer.score(createBullishKline(), []);
      final bearResult = ConfluenceScorer.score(createBearishKline(), []);

      expect(bullResult.score, greaterThan(bearResult.score));
    });

    test('详情包含10个维度', () {
      final kline = createNeutralKline();
      final result = ConfluenceScorer.score(kline, []);

      expect(result.details.length, equals(10));
    });

    test('多头和空头计数正确', () {
      final bullResult = ConfluenceScorer.score(createBullishKline(), []);
      // 多头kline: MA bull, MACD bull, RSI bull, KDJ bull, BOLL bull, VOL bull, WR bull, CCI bull = 8
      expect(bullResult.bullCount, equals(8));
      expect(bullResult.bearCount, equals(0));

      final bearResult = ConfluenceScorer.score(createBearishKline(), []);
      // 空头kline: MA bear, MACD bear, RSI bear, KDJ bear, BOLL bear, VOL bear, WR bear, CCI bear = 8
      expect(bearResult.bearCount, equals(8));
      expect(bullResult.bearCount, equals(0));
    });

    test('缺口信号正确识别', () {
      final kline = createNeutralKline();
      final signals = [
        SignalItem(type: 'buy', signal: '向上跳空', description: 'test'),
      ];
      final result = ConfluenceScorer.score(kline, signals);

      final gapDetail = result.details.firstWhere((d) => d['name'] == '缺口');
      expect(gapDetail['bull'], isTrue);
      expect(gapDetail['bear'], isFalse);
    });

    test('背离信号加权处理', () {
      final kline = createNeutralKline();
      final signals = [
        SignalItem(type: 'buy', signal: '底背离', description: 'test'),
      ];
      final result = ConfluenceScorer.score(kline, signals);

      // 底背离添加 DIVER，去重后为1个
      expect(result.bullCount, equals(1));
      final divergenceDetail =
          result.details.firstWhere((d) => d['name'] == '背离');
      expect(divergenceDetail['bull'], isTrue);
      expect(divergenceDetail['weighted'], isTrue);
    });

    test('中性数据评分为5.0', () {
      final kline = createNeutralKline();
      final result = ConfluenceScorer.score(kline, []);

      // 无多无空，bullDistinct=0, bearDistinct=0
      // confluenceScore = (5.0 + 0 - 0) = 5.0
      expect(result.score, equals(5.0));
      expect(result.bullCount, equals(0));
      expect(result.bearCount, equals(0));
    });

    test('详情维度名称正确', () {
      final kline = createNeutralKline();
      final result = ConfluenceScorer.score(kline, []);

      final names = result.details.map((d) => d['name'] as String).toList();
      expect(names,
          equals(['MA', 'MACD', 'RSI', 'KDJ', 'BOLL', '量价', 'WR', 'CCI', '缺口', '背离']));
    });
  });
}
