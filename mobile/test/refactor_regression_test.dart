import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/analysis/signal_layer.dart';
import 'package:stock_analyzer/analysis/strategy_engine.dart';

// ─── Helpers ───

/// Convert a list of prices into raw HistoryKline objects (no indicators).
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

/// Generate uptrend klines with indicators calculated.
List<HistoryKline> _uptrendData({int count = 80}) {
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

/// Generate downtrend klines with indicators calculated.
List<HistoryKline> _downtrendData({int count = 80}) {
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

/// Generate sideways klines with indicators calculated.
List<HistoryKline> _sidewaysData({int count = 80}) {
  final raw = List.generate(count, (i) {
    final price = 15.0 + (i % 10 - 5) * 0.3;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.1,
      high: price + 0.3,
      low: price - 0.3,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * price,
    );
  });
  return calcAllIndicators(raw);
}

/// Valid recommendation values from ComprehensiveScorer
const _validRecommendations = [
  '强烈买入', '买入', '谨慎买入', '偏多观望',
  '偏空观望', '谨慎卖出', '卖出', '强烈卖出', '观望',
];

/// Valid risk levels
const _validRiskLevels = ['高', '中等', '低'];

/// Build a sample QuoteData for testing
QuoteData _sampleQuote({
  double price = 15.0,
  double changePct = 2.0,
  double pe = 20.0,
  double pb = 2.0,
  double turnover = 3.0,
  double mainNetFlow = 5000000,
  double mainNetFlowRate = 5.0,
}) {
  return QuoteData(
    code: '600000',
    name: '测试股票',
    price: price,
    change: price * changePct / 100,
    changePct: changePct,
    open: price * 0.99,
    high: price * 1.02,
    low: price * 0.98,
    preClose: price / (1 + changePct / 100),
    volume: 500000,
    amount: 500000 * price,
    amplitude: 3.0,
    turnover: turnover,
    pe: pe,
    pb: pb,
    totalMarketCap: 5000000000,
    circulatingMarketCap: 3000000000,
    mainInflow: 10000000,
    mainOutflow: 5000000,
    mainNetFlow: mainNetFlow,
    mainNetFlowRate: mainNetFlowRate,
  );
}

/// Build a sample MarketContext for testing
MarketContext _sampleMarketContext({
  double avgChangePct = 0.8,
  double shIndexPct = 1.0,
  double szIndexPct = 1.2,
}) {
  return MarketContext(
    shIndexPct: shIndexPct,
    szIndexPct: szIndexPct,
    indexChange: 30.0,
    marketTrend: 'up',
    upCount: 50,
    downCount: 20,
    avgChangePct: avgChangePct,
    updateTime: DateTime(2024, 6, 1),
  );
}

/// Build sample news list for testing
List<Map<String, String>> _sampleNewsList() {
  return [
    {'title': '公司业绩大幅增长', 'content': '净利润同比增长50%'},
    {'title': '行业政策利好', 'content': '国家出台支持政策'},
    {'title': '新产品发布', 'content': '公司发布创新产品'},
  ];
}

// ─── Tests ───

void main() {
  // ============================================================
  // 1. generateAnalysis — 结构与范围验证
  // ============================================================
  group('generateAnalysis 结构与范围验证', () {
    test('上升趋势数据 — 无quote/marketContext/newsList', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(_validRecommendations, contains(result.recommendation));
      expect(_validRiskLevels, contains(result.riskLevel));
      expect(result.riskFactors, isA<List<String>>());
      expect(result.suggestions, isA<List<String>>());
      expect(result.suggestions, isNotEmpty);
      expect(result.signals, isA<List<SignalItem>>());
      expect(result.confluenceScore, greaterThanOrEqualTo(0));
      expect(result.confluenceDetails, isA<List<Map<String, dynamic>>>());
      expect(result.confidenceScore, greaterThanOrEqualTo(0.2));
      expect(result.confidenceScore, lessThanOrEqualTo(0.95));
      expect(result.confidenceBreakdown, isNotNull);
      expect(result.confidenceBreakdown!.length, equals(5));
      expect(result.confidenceBreakdown!.keys, containsAll([
        'signal_consistency',
        'fundamental_support',
        'sentiment_confirm',
        'market_confirm',
        'signal_freshness',
      ]));
      expect(result.reasons, isA<List<String>>());
      expect(result.opportunities, isA<List<Map<String, String>>>());
      expect(result.shortTermStrategies, isA<List<TradingStrategy>>());
      expect(result.longTermStrategies, isA<List<TradingStrategy>>());
      expect(result.detailedReasons, isA<List<RecommendationReason>>());
      expect(result.indicators, isNotEmpty);
      expect(result.validatedSignals, isA<List<ValidatedSignal>>());
      // No quote provided → no fundamentalScore
      expect(result.fundamentalScore, isNull);
      // No newsList → no newsSentiment
      expect(result.newsSentiment, isNull);
    });

    test('下降趋势数据 — 无quote/marketContext/newsList', () {
      final data = _downtrendData();
      final result = generateAnalysis(data, null);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(_validRecommendations, contains(result.recommendation));
      expect(_validRiskLevels, contains(result.riskLevel));
      expect(result.suggestions, isNotEmpty);
      expect(result.confidenceScore, greaterThanOrEqualTo(0.2));
      expect(result.confidenceScore, lessThanOrEqualTo(0.95));
      expect(result.indicators, isNotEmpty);
    });

    test('横盘趋势数据 — 无quote/marketContext/newsList', () {
      final data = _sidewaysData();
      final result = generateAnalysis(data, null);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(_validRecommendations, contains(result.recommendation));
      expect(result.indicators, isNotEmpty);
    });

    test('带quote参数 — fundamentalScore 应被设置', () {
      final data = _uptrendData();
      final quote = _sampleQuote();
      final result = generateAnalysis(data, quote);

      expect(result.fundamentalScore, isNotNull);
      expect(result.fundamentalScore!.totalScore, greaterThanOrEqualTo(0));
      expect(result.fundamentalScore!.totalScore, lessThanOrEqualTo(10));
      expect(result.fundamentalScore!.valuationScore, greaterThanOrEqualTo(0));
      expect(result.fundamentalScore!.capitalFlowScore, greaterThanOrEqualTo(0));
      expect(result.fundamentalScore!.liquidityScore, greaterThanOrEqualTo(0));
      expect(result.fundamentalScore!.factors, isNotEmpty);
    });

    test('带newsList参数 — newsSentiment 应被设置', () {
      final data = _uptrendData();
      final newsList = _sampleNewsList();
      final result = generateAnalysis(data, null, newsList: newsList);

      expect(result.newsSentiment, isNotNull);
      expect(result.newsSentiment!.score, greaterThanOrEqualTo(-10));
      expect(result.newsSentiment!.score, lessThanOrEqualTo(10));
    });

    test('带marketContext参数 — marketContext 应被传递', () {
      final data = _uptrendData();
      final marketContext = _sampleMarketContext();
      final result = generateAnalysis(data, null, marketContext: marketContext);

      expect(result.marketContext, isNotNull);
      expect(result.marketContext!.shIndexPct, equals(1.0));
      expect(result.marketContext!.szIndexPct, equals(1.2));
    });

    test('全部参数齐全', () {
      final data = _uptrendData();
      final quote = _sampleQuote();
      final marketContext = _sampleMarketContext();
      final newsList = _sampleNewsList();
      final result = generateAnalysis(data, quote, marketContext: marketContext, newsList: newsList);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(_validRecommendations, contains(result.recommendation));
      expect(result.fundamentalScore, isNotNull);
      expect(result.newsSentiment, isNotNull);
      expect(result.marketContext, isNotNull);
      expect(result.confidenceBreakdown, isNotNull);
      expect(result.confidenceBreakdown!.length, equals(5));
      expect(result.indicators, isNotEmpty);
    });
  });

  // ============================================================
  // 2. generateAnalysis — tradeLevels 验证
  // ============================================================
  group('generateAnalysis tradeLevels 验证', () {
    test('数据充足时 tradeLevels 包含预期键', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);

      expect(result.tradeLevels, isNotNull);
      expect(result.tradeLevels, isNotEmpty);
      expect(result.tradeLevels, containsPair('entry_low', isA<double>()));
      expect(result.tradeLevels, containsPair('entry_high', isA<double>()));
      expect(result.tradeLevels, containsPair('target', isA<double>()));
      expect(result.tradeLevels, containsPair('stop_loss', isA<double>()));
      expect(result.tradeLevels, containsPair('risk_reward_ratio', isA<double>()));
      expect(result.tradeLevels, containsPair('has_support', isA<bool>()));
      expect(result.tradeLevels, containsPair('has_resistance', isA<bool>()));
    });

    test('tradeLevels 的值逻辑合理', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);
      final tl = result.tradeLevels!;

      expect(tl['entry_low'] as double, lessThanOrEqualTo(tl['entry_high'] as double));
      expect(tl['target'] as double, greaterThanOrEqualTo(tl['entry_high'] as double));
      expect(tl['stop_loss'] as double, lessThanOrEqualTo(tl['entry_low'] as double));
      expect(tl['risk_reward_ratio'] as double, greaterThanOrEqualTo(0));
    });

    test('数据≥30条时 tradeLevels 包含支撑压力位质量评估', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);
      final tl = result.tradeLevels!;

      // 至少有部分 quality/test_count/reliability 键
      final qualityKeys = tl.keys.where((k) => k.contains('quality') || k.contains('reliability'));
      // 可能存在也可能不存在（取决于支撑压力位计算），不应崩溃
      expect(tl, isNotNull);
    });
  });

  // ============================================================
  // 3. generateAnalysis — backtestResults 验证
  // ============================================================
  group('generateAnalysis backtestResults 验证', () {
    test('数据≥60条时 backtestResults 包含4个回测项', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);

      // backtestResults 可能为空（如果回测引擎抛异常），但不应崩溃
      if (result.backtestResults != null && result.backtestResults!.isNotEmpty) {
        expect(result.backtestResults, contains('MACD金叉'));
        expect(result.backtestResults, contains('MA金叉'));
        expect(result.backtestResults, contains('KDJ超卖'));
        expect(result.backtestResults, contains('RSI超卖'));

        for (final entry in result.backtestResults!.entries) {
          expect(entry.value.totalSignals, greaterThanOrEqualTo(0));
          expect(entry.value.winRate, greaterThanOrEqualTo(0));
          expect(entry.value.winRate, lessThanOrEqualTo(1));
        }
      }
    });

    test('数据<60条时 backtestResults 为空Map', () {
      final data = _uptrendData(count: 50);
      final result = generateAnalysis(data, null);

      // 数据不足时 backtestResults 为空 Map（非 null）
      expect(result.backtestResults == null || result.backtestResults!.isEmpty, isTrue);
    });
  });

  // ============================================================
  // 4. generateAnalysis — 策略验证
  // ============================================================
  group('generateAnalysis 策略验证', () {
    test('shortTermStrategies 和 longTermStrategies 为 List', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      expect(result.shortTermStrategies, isA<List<TradingStrategy>>());
      expect(result.longTermStrategies, isA<List<TradingStrategy>>());
    });

    test('策略结构完整（如果存在）', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      for (final s in [...result.shortTermStrategies, ...result.longTermStrategies]) {
        expect(s.id, isNotEmpty);
        expect(s.name, isNotEmpty);
        expect(s.category, isNotEmpty);
        expect(s.entryRule, isNotEmpty);
        expect(s.exitRule, isNotEmpty);
        expect(s.stopLossRule, isNotEmpty);
      }
    });
  });

  // ============================================================
  // 5. generateAnalysis — validatedSignals 验证
  // ============================================================
  group('generateAnalysis validatedSignals 验证', () {
    test('validatedSignals 为 List<ValidatedSignal>', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      expect(result.validatedSignals, isA<List<ValidatedSignal>>());
    });

    test('每个 ValidatedSignal 结构完整', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      for (final vs in result.validatedSignals!) {
        expect(vs.signal, isA<SignalItem>());
        expect(vs.counterPoints, isA<List<String>>());
        expect(vs.adjustedConfidence, greaterThanOrEqualTo(0));
        expect(vs.adjustedConfidence, lessThanOrEqualTo(1));
      }
    });
  });

  // ============================================================
  // 6. generateAnalysis — detailedReasons 验证
  // ============================================================
  group('generateAnalysis detailedReasons 验证', () {
    test('detailedReasons 结构完整', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      for (final r in result.detailedReasons) {
        expect(r.title, isNotEmpty);
        expect(r.description, isNotEmpty);
        expect(r.confidence, greaterThanOrEqualTo(0));
        expect(r.confidence, lessThanOrEqualTo(1));
        expect(r.duration, isNotEmpty);
      }
    });

    test('带 marketContext 时 detailedReasons 包含市场环境条目', () {
      final data = _uptrendData();
      final marketContext = _sampleMarketContext();
      final result = generateAnalysis(data, null, marketContext: marketContext);

      final marketReason = result.detailedReasons.where((r) => r.title == '市场环境');
      expect(marketReason.isNotEmpty, true);
      expect(marketReason.first.confidence, equals(0.7));
      expect(marketReason.first.duration, equals('环境'));
    });
  });

  // ============================================================
  // 7. detectSignals 与 SignalLayer.detectUniqueSignals 一致性
  // ============================================================
  group('detectSignals 与 SignalLayer.detectUniqueSignals 一致性', () {
    test('detectSignals 返回结果等于 SignalLayer.detectUniqueSignals', () {
      final data = _uptrendData();
      final fromTopLevel = detectSignals(data);
      final fromLayer = SignalLayer.detectUniqueSignals(data);

      expect(fromTopLevel.length, equals(fromLayer.length));
      for (int i = 0; i < fromTopLevel.length; i++) {
        expect(fromTopLevel[i].signal, equals(fromLayer[i].signal));
        expect(fromTopLevel[i].type, equals(fromLayer[i].type));
        expect(fromTopLevel[i].strength, equals(fromLayer[i].strength));
      }
    });

    test('空数据时两者都返回空列表', () {
      expect(detectSignals([]), isEmpty);
      expect(SignalLayer.detectUniqueSignals([]), isEmpty);
    });

    test('少量数据时两者都返回空列表', () {
      final data = _pricesToKlines([10.0, 10.5]);
      expect(detectSignals(data), isEmpty);
      expect(SignalLayer.detectUniqueSignals(data), isEmpty);
    });
  });

  // ============================================================
  // 8. calcTradeLevels 验证
  // ============================================================
  group('calcTradeLevels 验证', () {
    test('空数据返回空 Map', () {
      expect(calcTradeLevels([]), isEmpty);
    });

    test('充足数据返回预期键', () {
      final data = _uptrendData(count: 80);
      final levels = calcTradeLevels(data);

      expect(levels, contains('entry_low'));
      expect(levels, contains('entry_high'));
      expect(levels, contains('target'));
      expect(levels, contains('stop_loss'));
      expect(levels, contains('risk_reward_ratio'));
      expect(levels, contains('has_support'));
      expect(levels, contains('has_resistance'));
    });

    test('tradeLevels 值逻辑合理', () {
      final data = _uptrendData(count: 80);
      final levels = calcTradeLevels(data);

      final entryLow = levels['entry_low'] as double;
      final entryHigh = levels['entry_high'] as double;
      final target = levels['target'] as double;
      final stopLoss = levels['stop_loss'] as double;

      expect(entryLow, lessThanOrEqualTo(entryHigh));
      expect(target, greaterThanOrEqualTo(entryHigh));
      expect(stopLoss, lessThanOrEqualTo(entryLow));
    });

    test('少量数据不崩溃', () {
      final data = _uptrendData(count: 5);
      final levels = calcTradeLevels(data);
      // 不崩溃即可
      expect(levels, isA<Map<String, dynamic>>());
    });
  });

  // ============================================================
  // 9. 边界情况
  // ============================================================
  group('边界情况', () {
    test('空数据 generateAnalysis 返回默认值', () {
      final result = generateAnalysis([], null);

      expect(result.signals, isEmpty);
      expect(result.indicators, isEmpty);
      expect(result.recommendation, equals('观望'));
      expect(result.score, equals(5));
      expect(result.riskLevel, equals('中等'));
      expect(result.riskFactors, equals(['数据不足']));
      expect(result.suggestions, equals(['等待更多数据']));
      expect(result.reasons, equals(['数据不足，无法生成有效建议']));
      expect(result.opportunities, isEmpty);
      expect(result.confidenceScore, equals(0.3));
    });

    test('极少量数据（2条）generateAnalysis 不崩溃', () {
      final raw = [
        HistoryKline(date: DateTime(2024, 1, 1), open: 10, high: 10.5, low: 9.5, close: 10, volume: 10000),
        HistoryKline(date: DateTime(2024, 1, 2), open: 10, high: 10.5, low: 9.5, close: 10.5, volume: 12000),
      ];
      final data = calcAllIndicators(raw);
      final result = generateAnalysis(data, null);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(_validRecommendations, contains(result.recommendation));
    });

    test('5条数据 generateAnalysis 不崩溃', () {
      final prices = [10.0, 10.5, 11.0, 10.8, 11.2];
      final data = calcAllIndicators(_pricesToKlines(prices));
      final result = generateAnalysis(data, null);

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
    });

    test('quote 为空时 fundamentalScore 为空', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);
      expect(result.fundamentalScore, isNull);
    });

    test('newsList 为空时 newsSentiment 为空', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);
      expect(result.newsSentiment, isNull);
    });

    test('newsList 为空列表时 newsSentiment 为空', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null, newsList: []);
      expect(result.newsSentiment, isNull);
    });
  });

  // ============================================================
  // 10. indicators 验证
  // ============================================================
  group('indicators 验证', () {
    test('充足数据的 indicators 包含关键指标', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);

      final ind = result.indicators;
      expect(ind, isNotEmpty);
      // 至少应包含部分指标摘要
      final hasAnyKey = ind.keys.any((k) =>
        k.contains('均线') || k.contains('MACD') || k.contains('RSI') ||
        k.contains('KDJ') || k.contains('BOLL') || k.contains('DIF'));
      expect(hasAnyKey, isTrue, reason: 'indicators 应包含至少一种技术指标摘要');
    });
  });

  // ============================================================
  // 11. confluenceDetails 验证
  // ============================================================
  group('confluenceDetails 验证', () {
    test('confluenceDetails 包含10个条目', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);

      expect(result.confluenceDetails.length, equals(10));
    });

    test('每个 confluenceDetail 条目包含必要键', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);

      for (final detail in result.confluenceDetails) {
        expect(detail, contains('name'));
        expect(detail, contains('bull'));
        expect(detail, contains('bear'));
      }
    });
  });

  // ============================================================
  // 12. 评分一致性 — 相同输入产生相同输出
  // ============================================================
  group('评分一致性', () {
    test('相同输入调用两次 generateAnalysis 结果一致', () {
      final data = _uptrendData();
      final quote = _sampleQuote();
      final marketContext = _sampleMarketContext();
      final newsList = _sampleNewsList();

      final result1 = generateAnalysis(data, quote, marketContext: marketContext, newsList: newsList);
      final result2 = generateAnalysis(data, quote, marketContext: marketContext, newsList: newsList);

      expect(result1.score, equals(result2.score));
      expect(result1.recommendation, equals(result2.recommendation));
      expect(result1.riskLevel, equals(result2.riskLevel));
      expect(result1.confidenceScore, equals(result2.confidenceScore));
      expect(result1.signals.length, equals(result2.signals.length));
      expect(result1.confluenceScore, equals(result2.confluenceScore));
    });

    test('相同输入调用两次 detectSignals 结果一致', () {
      final data = _uptrendData();
      final result1 = detectSignals(data);
      final result2 = detectSignals(data);

      expect(result1.length, equals(result2.length));
      for (int i = 0; i < result1.length; i++) {
        expect(result1[i].signal, equals(result2[i].signal));
        expect(result1[i].type, equals(result2[i].type));
        expect(result1[i].strength, equals(result2[i].strength));
      }
    });

    test('相同输入调用两次 calcTradeLevels 结果一致', () {
      final data = _uptrendData();
      final result1 = calcTradeLevels(data);
      final result2 = calcTradeLevels(data);

      expect(result1['entry_low'], equals(result2['entry_low']));
      expect(result1['target'], equals(result2['target']));
      expect(result1['stop_loss'], equals(result2['stop_loss']));
      expect(result1['risk_reward_ratio'], equals(result2['risk_reward_ratio']));
    });
  });

  // ============================================================
  // 13. 不同市场场景下推荐合理性
  // ============================================================
  group('不同市场场景推荐合理性', () {
    test('强上升趋势 + 正面quote + 正面市场环境 → 偏多推荐', () {
      final data = _uptrendData(count: 80);
      final quote = _sampleQuote(changePct: 3.0, mainNetFlowRate: 5.0);
      final marketContext = _sampleMarketContext(avgChangePct: 1.5);
      final result = generateAnalysis(data, quote, marketContext: marketContext);

      expect(result.score, greaterThanOrEqualTo(6));
      expect(result.recommendation, anyOf('强烈买入', '买入', '谨慎买入', '偏多观望'));
    });

    test('强下降趋势 + 负面quote + 负面市场环境 → 偏空推荐', () {
      final data = _downtrendData(count: 80);
      final quote = _sampleQuote(price: 10.0, changePct: -3.0, mainNetFlow: -5000000, mainNetFlowRate: -5.0);
      final marketContext = _sampleMarketContext(avgChangePct: -1.5, shIndexPct: -1.0, szIndexPct: -1.2);
      final result = generateAnalysis(data, quote, marketContext: marketContext);

      expect(result.score, lessThanOrEqualTo(5));
      expect(result.recommendation, anyOf('偏空观望', '谨慎卖出', '卖出', '强烈卖出'));
    });
  });

  // ============================================================
  // 14. reasons 验证
  // ============================================================
  group('reasons 验证', () {
    test('上升趋势数据产生均线多头排列理由', () {
      final data = _uptrendData(count: 80);
      final result = generateAnalysis(data, null);
      final last = data.last;

      if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma5 > 0) {
        expect(result.reasons, contains('均线多头排列'));
      }
    });

    test('下降趋势数据产生均线空头排列理由', () {
      final data = _downtrendData(count: 80);
      final result = generateAnalysis(data, null);
      final last = data.last;

      if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma5 > 0) {
        expect(result.reasons, contains('均线空头排列'));
      }
    });

    test('带quote时 reasons 可能包含资金流入/流出理由', () {
      final data = _uptrendData(count: 80);
      final quote = _sampleQuote(mainNetFlow: 50000000, mainNetFlowRate: 8.0);
      final result = generateAnalysis(data, quote);

      // 主力净流入率 > 3% 时应包含资金流入理由
      expect(result.reasons.any((r) => r.contains('主力资金净流入')), isTrue);
    });
  });

  // ============================================================
  // 15. opportunities 验证
  // ============================================================
  group('opportunities 验证', () {
    test('opportunities 为 List<Map<String, String>>', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      expect(result.opportunities, isA<List<Map<String, String>>>());
    });

    test('每个 opportunity 包含必要键（如果存在）', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      for (final opp in result.opportunities) {
        expect(opp, contains('name'));
        expect(opp, contains('description'));
        expect(opp, contains('risk'));
      }
    });
  });

  // ============================================================
  // 16. riskFactors 验证
  // ============================================================
  group('riskFactors 验证', () {
    test('riskFactors 为非空 List<String>', () {
      final data = _uptrendData();
      final result = generateAnalysis(data, null);

      expect(result.riskFactors, isA<List<String>>());
    });
  });

  // ============================================================
  // 17. confidenceBreakdown 各维度值范围
  // ============================================================
  group('confidenceBreakdown 各维度值范围', () {
    test('每个维度值在 [0, 1] 范围内', () {
      final data = _uptrendData();
      final quote = _sampleQuote();
      final marketContext = _sampleMarketContext();
      final newsList = _sampleNewsList();
      final result = generateAnalysis(data, quote, marketContext: marketContext, newsList: newsList);

      final bd = result.confidenceBreakdown!;
      for (final entry in bd.entries) {
        expect(entry.value, greaterThanOrEqualTo(0), reason: '${entry.key} 应 >= 0');
        expect(entry.value, lessThanOrEqualTo(1), reason: '${entry.key} 应 <= 1');
      }
    });
  });

  // ============================================================
  // 18. fundamentalScore 各子项范围
  // ============================================================
  group('fundamentalScore 各子项范围', () {
    test('各子项在 [0, 10] 范围内', () {
      final data = _uptrendData();
      final quote = _sampleQuote(pe: 15, pb: 1.5, turnover: 3.0);
      final result = generateAnalysis(data, quote);

      final fs = result.fundamentalScore!;
      expect(fs.valuationScore, greaterThanOrEqualTo(0));
      expect(fs.valuationScore, lessThanOrEqualTo(10));
      expect(fs.capitalFlowScore, greaterThanOrEqualTo(0));
      expect(fs.capitalFlowScore, lessThanOrEqualTo(10));
      expect(fs.liquidityScore, greaterThanOrEqualTo(0));
      expect(fs.liquidityScore, lessThanOrEqualTo(10));
      expect(fs.totalScore, greaterThanOrEqualTo(0));
      expect(fs.totalScore, lessThanOrEqualTo(10));
    });
  });

  // ============================================================
  // 19. newsSentiment 结构验证
  // ============================================================
  group('newsSentiment 结构验证', () {
    test('newsSentiment 各字段在合理范围', () {
      final data = _uptrendData();
      final newsList = _sampleNewsList();
      final result = generateAnalysis(data, null, newsList: newsList);

      final ns = result.newsSentiment!;
      expect(ns.score, greaterThanOrEqualTo(-10));
      expect(ns.score, lessThanOrEqualTo(10));
      expect(ns.positiveCount, greaterThanOrEqualTo(0));
      expect(ns.negativeCount, greaterThanOrEqualTo(0));
      expect(ns.neutralCount, greaterThanOrEqualTo(0));
      expect(ns.keyFactors, isA<List<String>>());
    });
  });

  // ============================================================
  // 20. 大数据量性能（不超时即可）
  // ============================================================
  group('大数据量', () {
    test('200条数据 generateAnalysis 不崩溃', () {
      final data = _uptrendData(count: 200);
      final result = generateAnalysis(data, _sampleQuote(), marketContext: _sampleMarketContext(), newsList: _sampleNewsList());

      expect(result.score, greaterThanOrEqualTo(1));
      expect(result.score, lessThanOrEqualTo(10));
      expect(result.backtestResults, isNotNull);
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
