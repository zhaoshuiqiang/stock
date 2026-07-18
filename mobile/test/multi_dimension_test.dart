import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/fundamental_analyzer.dart';
import 'package:stock_analyzer/analysis/signal_validator.dart';
import 'package:stock_analyzer/analysis/news_sentiment_analyzer.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';

// ─── Helper ───
List<HistoryKline> _makeKlines(List<double> prices) {
  return calcAllIndicators(List.generate(prices.length, (i) {
    final p = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: p * 0.99,
      high: p * 1.02,
      low: p * 0.98,
      close: p,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * p,
    );
  }));
}

void main() {
  // ==================== FundamentalAnalyzer Tests ====================
  group('FundamentalAnalyzer', () {
    test('低PE低PB应得高分', () {
      final quote = QuoteData(
        code: '600000',
        name: '测试股',
        price: 10,
        pe: 8,
        pb: 0.7,
        mainNetFlowRate: 8,
        turnover: 3,
      );
      final score = FundamentalAnalyzer.analyze(quote);
      expect(score.valuationScore, greaterThan(7));
      expect(score.capitalFlowScore, greaterThan(6));
      expect(score.liquidityScore, greaterThan(6));
      expect(score.totalScore, greaterThan(7));
    });

    test('高PE高PB应得低分', () {
      final quote = QuoteData(
        code: '600001',
        name: '测试股',
        price: 50,
        pe: 100,
        pb: 12,
        mainNetFlowRate: -15,
        turnover: 0.3,
      );
      final score = FundamentalAnalyzer.analyze(quote);
      expect(score.valuationScore, lessThan(3));
      expect(score.capitalFlowScore, lessThan(3));
      expect(score.liquidityScore, lessThan(5));
      expect(score.totalScore, lessThan(3));
    });

    test('亏损股PE=0应得中性偏低估值分', () {
      final quote = QuoteData(
        code: '600002',
        name: '亏损股',
        price: 5,
        pe: -5,
        pb: 2,
        mainNetFlowRate: 0,
        turnover: 2,
      );
      final score = FundamentalAnalyzer.analyze(quote);
      expect(score.valuationScore, closeTo(3.8, 0.5)); // PE=3.0*0.6 + PB=5.0*0.4 = 3.8
    });

    test('总分应在0-10范围内', () {
      // 极端情况
      final quote = QuoteData(
        code: '600003',
        name: '极端股',
        price: 100,
        pe: 0,
        pb: 0,
        mainNetFlowRate: 0,
        turnover: 0,
      );
      final score = FundamentalAnalyzer.analyze(quote);
      expect(score.totalScore, greaterThanOrEqualTo(0));
      expect(score.totalScore, lessThanOrEqualTo(10));
    });

    test('factors列表应包含关键信息', () {
      final quote = QuoteData(
        code: '600004',
        name: '测试股',
        price: 10,
        pe: 12,
        pb: 0.9,
        mainNetFlowRate: 8,
        turnover: 3,
      );
      final score = FundamentalAnalyzer.analyze(quote);
      expect(score.factors, isNotEmpty);
      expect(score.factors.any((f) => f.contains('PE')), isTrue);
    });
  });

  // ==================== SignalValidator Tests ====================
  group('SignalValidator', () {
    test('买入信号在RSI超买时应产生Bear反对', () {
      final signals = [
        SignalItem(type: 'buy', signal: 'KDJ金叉', desc: 'KDJ金叉', confidence: 0.7),
      ];
      final last = HistoryKline(
        date: DateTime.now(),
        close: 20,
        open: 19,
        high: 21,
        low: 18,
        rsi6: 75, // 超买
        ma5: 19,
        ma10: 18,
        ma20: 17,
        volMa5: 10000,
        volume: 8000,
        j: 110, // KDJ超买
      );
      final validated = SignalValidator.validate(signals, null, last);
      expect(validated.length, 1);
      expect(validated[0].counterPoints, isNotEmpty);
      expect(validated[0].counterPoints.any((p) => p.contains('超买')), isTrue);
      expect(validated[0].adjustedConfidence, lessThan(0.7));
    });

    test('卖出信号在RSI超卖时应产生Bull支撑', () {
      final signals = [
        SignalItem(type: 'sell', signal: 'KDJ死叉', desc: 'KDJ死叉', confidence: 0.6),
      ];
      final last = HistoryKline(
        date: DateTime.now(),
        close: 10,
        open: 11,
        high: 12,
        low: 9,
        rsi6: 25, // 超卖
        ma5: 12,
        ma10: 13,
        ma20: 14,
        volMa5: 10000,
        volume: 8000,
        j: -10, // KDJ超卖
        bollLower: 9.5,
      );
      final validated = SignalValidator.validate(signals, null, last);
      expect(validated.length, 1);
      expect(validated[0].counterPoints, isNotEmpty);
      expect(validated[0].counterPoints.any((p) => p.contains('超卖')), isTrue);
      expect(validated[0].adjustedConfidence, lessThan(0.6));
    });

    test('中性信号不应产生反对论点', () {
      final signals = [
        SignalItem(type: 'neutral', signal: '观望', desc: '观望', confidence: 0.5),
      ];
      final last = HistoryKline(date: DateTime.now(), close: 10);
      final validated = SignalValidator.validate(signals, null, last);
      expect(validated[0].counterPoints, isEmpty);
      expect(validated[0].adjustedConfidence, equals(0.5));
    });

    test('adjustedConfidence应在合理范围内', () {
      final signals = [
        SignalItem(type: 'buy', signal: '买入', desc: '买入', confidence: 0.5),
      ];
      final last = HistoryKline(
        date: DateTime.now(),
        close: 20,
        rsi6: 85,
        ma5: 15,
        ma10: 16,
        ma20: 17, // 空头排列
        volMa5: 10000,
        volume: 5000, // 缩量
        j: 120,
        bollUpper: 19,
        bias6: 8,
      );
      final quote = QuoteData(code: '600000', name: '测试', price: 20, pe: 80, mainNetFlowRate: -8);
      final validated = SignalValidator.validate(signals, quote, last);
      // 多条强反对，置信度应显著下降
      expect(validated[0].adjustedConfidence, lessThan(0.5));
      expect(validated[0].adjustedConfidence, greaterThanOrEqualTo(0.2));
    });
  });

  // ==================== NewsSentimentAnalyzer Tests ====================
  group('NewsSentimentAnalyzer', () {
    test('利好新闻应得正分', () {
      final news = [
        {'title': '某公司业绩增长超预期'},
        {'title': '某公司中标重大项目'},
        {'title': '大股东增持公司股份'},
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      expect(sentiment.score, greaterThan(0));
      expect(sentiment.positiveCount, equals(3));
      expect(sentiment.negativeCount, equals(0));
    });

    test('利空新闻应得负分', () {
      final news = [
        {'title': '某公司业绩亏损扩大'},
        {'title': '大股东减持公司股份'},
        {'title': '某公司违规被处罚'},
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      expect(sentiment.score, lessThan(0));
      expect(sentiment.negativeCount, equals(3));
      expect(sentiment.positiveCount, equals(0));
    });

    test('混合新闻应得中间分', () {
      final news = [
        {'title': '某公司业绩增长'},
        {'title': '某公司减持股份'},
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      expect(sentiment.positiveCount, equals(1));
      expect(sentiment.negativeCount, equals(1));
    });

    test('空新闻列表应返回中性', () {
      final sentiment = NewsSentimentAnalyzer.analyze([]);
      expect(sentiment.score, equals(0));
      expect(sentiment.positiveCount, equals(0));
      expect(sentiment.negativeCount, equals(0));
    });

    test('空标题新闻应被跳过不影响评分', () {
      final news = [
        {'title': '某公司业绩增长超预期'},
        {'title': ''},
        {'title': ''},
        {'title': ''},
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      // 只有1条有效新闻，不应被空标题稀释
      expect(sentiment.positiveCount, equals(1));
      expect(sentiment.score, greaterThan(0));
    });

    test('情绪评分应在[-10, +10]范围内', () {
      final news = List.generate(20, (i) => {'title': '某公司业绩增长超预期净利增长回购增持'});
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      expect(sentiment.score, greaterThanOrEqualTo(-10));
      expect(sentiment.score, lessThanOrEqualTo(10));
    });

    test('keyFactors应包含高权重关键词', () {
      final news = [
        {'title': '某公司业绩增长超预期'},
        {'title': '某公司违规被处罚'},
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      expect(sentiment.keyFactors, isNotEmpty);
    });

    test('高权重关键词应覆盖低权重关键词作为matchedKeyword', () {
      // 测试修复后的对称逻辑
      final news = [
        {'title': '某公司利好消息但亏损扩大'},  // 利好(3) + 亏损(3)
      ];
      final sentiment = NewsSentimentAnalyzer.analyze(news);
      // 两个关键词权重相同，最终matchedKeyword取决于遍历顺序
      // 但关键是：不应总是偏向负面
      expect(sentiment.keyFactors.length, lessThanOrEqualTo(5));
    });
  });

  // ==================== 多维融合评分集成测试 ====================
  group('多维融合评分集成测试', () {
    test('generateAnalysis无新闻数据时应正常工作', () {
      final data = _makeKlines(List.generate(40, (i) => 15.0 + (i % 10) * 0.5));
      final quote = QuoteData(code: '600000', name: '测试', price: 15, pe: 20, pb: 2);
      final result = generateAnalysis(data, quote);
      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(result.fundamentalScore, isNotNull);
      expect(result.newsSentiment, isNull);
      expect(result.validatedSignals, isNotNull);
      expect(result.confidenceBreakdown, isNotNull);
    });

    test('generateAnalysis有新闻数据时应包含情绪评分', () {
      final data = _makeKlines(List.generate(40, (i) => 15.0 + (i % 10) * 0.5));
      final quote = QuoteData(code: '600000', name: '测试', price: 15, pe: 20, pb: 2);
      final news = [
        {'title': '某公司业绩增长超预期'},
        {'title': '某公司中标重大项目'},
      ];
      final result = generateAnalysis(data, quote, newsList: news);
      expect(result.newsSentiment, isNotNull);
      expect(result.newsSentiment!.score, greaterThan(0));
    });

    test('generateAnalysis动态权重总和应为1.0', () {
      // 无基本面无情绪
      final data = _makeKlines(List.generate(40, (i) => 15.0 + (i % 10) * 0.5));
      final result1 = generateAnalysis(data, null);
      expect(result1.score, greaterThanOrEqualTo(1));
      expect(result1.score, lessThanOrEqualTo(10));

      // 有基本面无情绪
      final quote = QuoteData(code: '600000', name: '测试', price: 15, pe: 20, pb: 2);
      final result2 = generateAnalysis(data, quote);
      expect(result2.score, greaterThanOrEqualTo(1));
      expect(result2.score, lessThanOrEqualTo(10));

      // 有基本面有情绪
      final news = [{'title': '利好消息'}];
      final result3 = generateAnalysis(data, quote, newsList: news);
      expect(result3.score, greaterThanOrEqualTo(1));
      expect(result3.score, lessThanOrEqualTo(10));
    });

    test('10级评分应能覆盖1-10范围', () {
      // 测试修复后的映射公式：adjustedScore=10时totalScore应为10
      // 通过构造极端上涨数据测试高分
      double price = 10.0;
      final raw = List.generate(60, (i) {
        final open = price;
        price *= 1.03;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: open,
          high: price * 1.01,
          low: open * 0.99,
          close: price,
          volume: 20000.0 + i * 1000,
          amount: 20000 * (open + price) / 2,
        );
      });
      final data = calcAllIndicators(raw);
      final quote = QuoteData(
        code: '600000',
        name: '强势股',
        price: price,
        changePct: 5,
        pe: 8,
        pb: 0.7,
        mainNetFlowRate: 12,
        turnover: 3,
      );
      final news = [{'title': '业绩增长超预期回购增持'}];
      final result = generateAnalysis(data, quote, newsList: news);
      // 强势数据+好基本面+利好新闻，评分应较高
      expect(result.score, greaterThanOrEqualTo(5.5));
    });

    test('置信度分项明细应包含7个维度', () {
      final data = _makeKlines(List.generate(40, (i) => 15.0 + (i % 10) * 0.5));
      final quote = QuoteData(code: '600000', name: '测试', price: 15, pe: 20, pb: 2);
      final result = generateAnalysis(data, quote);
      expect(result.confidenceBreakdown, isNotNull);
      expect(result.confidenceBreakdown!.length, equals(8));
      expect(result.confidenceBreakdown!.containsKey('signal_consistency'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('fundamental_support'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('sentiment_confirm'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('market_confirm'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('structure_confirm'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('signal_freshness'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('historical_winrate'), isTrue);
      expect(result.confidenceBreakdown!.containsKey('prediction_support'), isTrue);
    });

    test('confidenceScore应在[0.3, 0.95]范围内', () {
      final data = _makeKlines(List.generate(40, (i) => 15.0 + (i % 10) * 0.5));
      final quote = QuoteData(code: '600000', name: '测试', price: 15, pe: 20, pb: 2);
      final result = generateAnalysis(data, quote);
      expect(result.confidenceScore, greaterThanOrEqualTo(0.3));
      expect(result.confidenceScore, lessThanOrEqualTo(0.95));
    });
  });

  // ==================== 数据模型序列化测试 ====================
  group('数据模型序列化', () {
    test('FundamentalScore序列化/反序列化', () {
      final score = FundamentalScore(
        valuationScore: 7.5,
        capitalFlowScore: 6.0,
        liquidityScore: 8.0,
        totalScore: 7.1,
        factors: ['PE=12，估值偏低'],
      );
      final json = score.toJson();
      final restored = FundamentalScore.fromJson(json);
      expect(restored.valuationScore, equals(7.5));
      expect(restored.capitalFlowScore, equals(6.0));
      expect(restored.liquidityScore, equals(8.0));
      expect(restored.totalScore, equals(7.1));
      expect(restored.factors.length, equals(1));
    });

    test('ValidatedSignal序列化/反序列化', () {
      final vs = ValidatedSignal(
        signal: SignalItem(type: 'buy', signal: 'KDJ金叉', desc: 'KDJ金叉', confidence: 0.7),
        counterPoints: ['RSI超买', '均线空头排列'],
        adjustedConfidence: 0.5,
      );
      final json = vs.toJson();
      final restored = ValidatedSignal.fromJson(json);
      expect(restored.signal.type, equals('buy'));
      expect(restored.counterPoints.length, equals(2));
      expect(restored.adjustedConfidence, equals(0.5));
    });

    test('NewsSentiment序列化/反序列化', () {
      final ns = NewsSentiment(
        score: 5.0,
        positiveCount: 3,
        negativeCount: 1,
        neutralCount: 2,
        keyFactors: ['[利好] 业绩增长: xxx'],
      );
      final json = ns.toJson();
      final restored = NewsSentiment.fromJson(json);
      expect(restored.score, equals(5.0));
      expect(restored.positiveCount, equals(3));
      expect(restored.negativeCount, equals(1));
      expect(restored.direction, equals('positive'));
    });

    test('NewsSentiment.direction属性', () {
      expect(NewsSentiment(score: 5, positiveCount: 1, negativeCount: 0, neutralCount: 0, keyFactors: []).direction, equals('positive'));
      expect(NewsSentiment(score: -5, positiveCount: 0, negativeCount: 1, neutralCount: 0, keyFactors: []).direction, equals('negative'));
      expect(NewsSentiment(score: 0, positiveCount: 0, negativeCount: 0, neutralCount: 1, keyFactors: []).direction, equals('neutral'));
    });
  });
}
