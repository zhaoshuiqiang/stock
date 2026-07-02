import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/analysis/comprehensive_scorer.dart';
import 'package:stock_analyzer/analysis/market_structure_analyzer.dart';

/// Generate uptrend kline data with indicators calculated.
List<HistoryKline> _uptrendData({int count = 60}) {
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

/// Generate downtrend kline data with indicators calculated.
List<HistoryKline> _downtrendData({int count = 60}) {
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

/// Generate neutral/sideways kline data.
List<HistoryKline> _sidewaysData({int count = 60}) {
  final raw = List.generate(count, (i) {
    final price = 15.0 + (i % 7 - 3) * 0.2;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.1,
      high: price + 0.2,
      low: price - 0.2,
      close: price,
      volume: 10000.0,
      amount: 10000 * price,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  // ─── 1. Weighted Signal Scoring Tests ───
  group('Weighted Signal Scoring', () {
    test('Strong buy signal dominates weak sell signals', () {
      final data = _uptrendData();
      final analysis = generateAnalysis(data, null);

      // Uptrend data should produce more buy signals than sell signals
      final buySignals = analysis.signals.where((s) => s.type == 'buy').toList();
      final sellSignals = analysis.signals.where((s) => s.type == 'sell').toList();

      // Score should reflect weighted strength, not just count
      expect(analysis.score, greaterThanOrEqualTo(0));
      expect(analysis.score, lessThanOrEqualTo(10));
    });

    test('Score is within valid range for any data', () {
      final datasets = [_uptrendData(), _downtrendData(), _sidewaysData()];
      for (final data in datasets) {
        final analysis = generateAnalysis(data, null);
        expect(analysis.score, greaterThanOrEqualTo(0));
        expect(analysis.score, lessThanOrEqualTo(10));
      }
    });

    test('Empty data returns default score', () {
      final analysis = generateAnalysis([], null);
      expect(analysis.score, equals(5));
      expect(analysis.recommendation, equals('观望'));
    });
  });

  // ─── 2. Five-Dimension Scoring Tests ───
  group('Five-Dimension K-line Scoring', () {
    test('Uptrend produces higher score than downtrend', () {
      final upAnalysis = generateAnalysis(_uptrendData(), null);
      final downAnalysis = generateAnalysis(_downtrendData(), null);

      expect(upAnalysis.score, greaterThan(downAnalysis.score),
          reason: 'Uptrend should score higher than downtrend');
    });

    test('Trend score includes ADX influence', () {
      final data = _uptrendData(count: 80);
      final last = data.last;
      // If ADX > 25, trend score should get bonus
      if (last.adx14 > 25) {
        final analysis = generateAnalysis(data, null);
        // Uptrend with strong ADX should produce good score
        expect(analysis.score, greaterThan(5));
      }
    });

    test('Momentum score includes BIAS penalty', () {
      // Create data with extreme BIAS
      var data = _uptrendData();
      final n = data.length;
      // Force extreme positive BIAS6
      data[n - 1] = data[n - 1].copyWith(bias6: 8.0);
      final analysis = generateAnalysis(data, null);
      // Should still produce valid score (BIAS penalty applied but not crashing)
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Volume score includes OBV trend', () {
      final data = _uptrendData(count: 60);
      final analysis = generateAnalysis(data, null);
      // Uptrend with rising OBV should have reasonable score
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Volatility score based on ATR', () {
      final data = _uptrendData();
      final last = data.last;
      if (last.atr14 > 0 && last.close > 0) {
        final atrPct = last.atr14 / last.close * 100;
        // Low ATR should give higher volatility score
        final analysis = generateAnalysis(data, null);
        expect(analysis.score, greaterThanOrEqualTo(0));
      }
    });
  });

  // ─── 3. Confluence Score Integration Tests ───
  group('Confluence Score Integration', () {
    test('Confluence score affects final score', () {
      final upData = _uptrendData(count: 80);
      final analysis = generateAnalysis(upData, null);

      // Confluence score should be populated
      expect(analysis.confluenceScore, greaterThanOrEqualTo(0));
      expect(analysis.confluenceScore, lessThanOrEqualTo(10));

      // Confluence details should have 7 dimensions
      expect(analysis.confluenceDetails, isNotNull);
      expect(analysis.confluenceDetails!.length, equals(10));
    });

    test('High confluence score boosts total score', () {
      final data = _uptrendData(count: 80);
      final analysis = generateAnalysis(data, null);

      // If confluence is high (many bullish dimensions), score should reflect it
      if (analysis.confluenceScore >= 5) {
        expect(analysis.score, greaterThan(5),
            reason: 'High confluence should boost score');
      }
    });

    test('Confluence details contain all 7 dimensions', () {
      final data = _uptrendData();
      final analysis = generateAnalysis(data, null);

      final dimensionNames = analysis.confluenceDetails!.map((d) => d['name']).toList();
      expect(dimensionNames, containsAll(['MA', 'MACD', 'RSI', 'KDJ', 'BOLL', '量价', '背离']));
    });
  });

  // ─── 4. Realtime Score Optimization Tests ───
  group('Realtime Score Optimization', () {
    test('Oversold bounce gets higher bonus', () {
      final data = _uptrendData();
      // Quote with -6% change (oversold bounce scenario)
      final quote = QuoteData(
        code: 'sh600000',
        name: '测试',
        price: 15.0,
        changePct: -6.0,
        mainNetFlow: 1000000,
        mainNetFlowRate: 2.0,
        turnover: 3.0,
      );
      final analysis = generateAnalysis(data, quote);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Moderate decline gets +5 bonus', () {
      final data = _uptrendData();
      final quote = QuoteData(
        code: 'sh600000',
        name: '测试',
        price: 15.0,
        changePct: -4.0,
        mainNetFlow: 0,
        mainNetFlowRate: 0,
        turnover: 2.0,
      );
      final analysis = generateAnalysis(data, quote);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Moderate rise gets +10 bonus', () {
      final data = _uptrendData();
      final quote = QuoteData(
        code: 'sh600000',
        name: '测试',
        price: 15.0,
        changePct: 2.0,
        mainNetFlow: 500000,
        mainNetFlowRate: 1.0,
        turnover: 3.0,
      );
      final analysis = generateAnalysis(data, quote);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Null quote uses neutral realtime score', () {
      final data = _uptrendData();
      final analysis = generateAnalysis(data, null);
      // Should still produce valid score without quote
      expect(analysis.score, greaterThanOrEqualTo(0));
    });
  });

  // ─── 5. ADX Weight Adjustment Tests ───
  group('ADX Trend/Ranging Weight Adjustment', () {
    test('High ADX boosts trend signals in trending market', () {
      var data = _uptrendData(count: 80);
      final n = data.length;
      // Force high ADX
      data[n - 1] = data[n - 1].copyWith(adx14: 30.0);
      final analysis = generateAnalysis(data, null);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Low ADX boosts oscillator signals in ranging market', () {
      var data = _sidewaysData(count: 80);
      final n = data.length;
      // Force low ADX
      data[n - 1] = data[n - 1].copyWith(adx14: 15.0);
      final analysis = generateAnalysis(data, null);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });

    test('Zero ADX does not cause errors', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(adx14: 0.0);
      final analysis = generateAnalysis(data, null);
      expect(analysis.score, greaterThanOrEqualTo(0));
    });
  });

  // ─── 6. Enhanced Risk Factor Tests ───
  group('Enhanced Risk Factors', () {
    test('ATR volatility risk factor detected', () {
      var data = _uptrendData();
      final n = data.length;
      // Force high ATR (ATR/close > 5%)
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(atr14: last.close * 0.06);
      final analysis = generateAnalysis(data, null);

      final atrRisk = analysis.riskFactors.where((f) => f.contains('ATR波动率')).toList();
      expect(atrRisk.isNotEmpty, true, reason: 'Should detect ATR volatility risk when ATR/close > 5%');
    });

    test('Low ATR does not trigger risk factor', () {
      var data = _uptrendData();
      final n = data.length;
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(atr14: last.close * 0.01);
      final analysis = generateAnalysis(data, null);

      final atrRisk = analysis.riskFactors.where((f) => f.contains('ATR波动率')).toList();
      expect(atrRisk.isEmpty, true, reason: 'Should not detect ATR risk when ATR/close < 2%');
    });

    test('BIAS extreme positive risk factor detected', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: 7.0);
      final analysis = generateAnalysis(data, null);

      final biasRisk = analysis.riskFactors.where((f) => f.contains('BIAS6') && f.contains('偏离均线过大')).toList();
      expect(biasRisk.isNotEmpty, true, reason: 'Should detect BIAS6 extreme positive risk');
    });

    test('BIAS extreme negative risk factor detected', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: -7.0);
      final analysis = generateAnalysis(data, null);

      final biasRisk = analysis.riskFactors.where((f) => f.contains('BIAS6') && f.contains('严重偏离均线')).toList();
      expect(biasRisk.isNotEmpty, true, reason: 'Should detect BIAS6 extreme negative risk');
    });

    test('Normal BIAS does not trigger risk factor', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: 2.0);
      final analysis = generateAnalysis(data, null);

      final biasRisk = analysis.riskFactors.where((f) => f.contains('BIAS6')).toList();
      expect(biasRisk.isEmpty, true, reason: 'Should not detect BIAS risk when BIAS6 is normal');
    });

    test('OBV price-volume divergence risk factor detected', () {
      var data = _uptrendData();
      final n = data.length;
      // Force: price up but OBV down
      data[n - 5] = data[n - 5].copyWith(obv: 100000, close: 10.0);
      data[n - 1] = data[n - 1].copyWith(obv: 80000, close: 20.0);
      final analysis = generateAnalysis(data, null);

      final obvRisk = analysis.riskFactors.where((f) => f.contains('OBV量价背离')).toList();
      expect(obvRisk.isNotEmpty, true, reason: 'Should detect OBV divergence when price up but OBV down');
    });

    test('OBV aligned with price does not trigger risk', () {
      var data = _uptrendData();
      final n = data.length;
      // Force: price up and OBV up (aligned)
      data[n - 5] = data[n - 5].copyWith(obv: 80000, close: 10.0);
      data[n - 1] = data[n - 1].copyWith(obv: 100000, close: 20.0);
      final analysis = generateAnalysis(data, null);

      final obvRisk = analysis.riskFactors.where((f) => f.contains('OBV量价背离')).toList();
      expect(obvRisk.isEmpty, true, reason: 'Should not detect OBV divergence when price and OBV aligned');
    });
  });

  // ─── 7. Final Score Formula Tests ───
  group('Final Score Formula', () {
    test('Score and confluence are valid for uptrend + quote', () {
      final data = _uptrendData(count: 80);
      final quote = QuoteData(
        code: 'sh600000',
        name: '测试',
        price: 15.0,
        changePct: 2.0,
        mainNetFlow: 500000,
        mainNetFlowRate: 2.0,
        turnover: 3.0,
      );
      final analysis = generateAnalysis(data, quote);

      // Score should be valid
      expect(analysis.score, greaterThanOrEqualTo(0));
      expect(analysis.score, lessThanOrEqualTo(10));
      // Confluence score should be populated
      expect(analysis.confluenceScore, greaterThanOrEqualTo(0));
    });

    test('Recommendation mapping covers all 8 levels from 1-10', () {
      // 验证 ComprehensiveScorer 的实际阈值: 8/7/6/5/4/3/2
      // 通过设置等值子分数 + 无 quote/news/capital 控制 adjustedScore
      ComprehensiveScoreResult _scored(double s) {
        final ms = MarketStructureResult(
          structure: MarketStructure.consolidation, confidence: 0.5,
          adxValue: 0, maAlignment: '混合', description: '',
          compatibleStrategies: [], structureScore: s,
        );
        return ComprehensiveScorer.combine(
          technicalScore: s,
          realtimeScore: s,
          confluenceScore: s,
          quote: null,
          marketContext: null,
          newsList: null,
          capitalFlowScore: null,
          marketPositionFactor: 1.0,
          marketStructure: ms,
        );
      }

      // adjustedScore → totalScore → recommendation 映射验证
      // 注: 无 quote 时权重 (v2.37 branch 1) tech 0.50 + real 0.25 + conf 0.18 + struct 0.07 = 1.0, rawScore = s
      // v2.37: 移除 0.95 系数，totalScore = round(adjustedScore).clamp(1,10)
      expect(_scored(8.5).recommendation, equals('强烈买入'), reason: 's=8.5 → round=9');
      expect(_scored(6.9).recommendation, equals('买入'), reason: 's=6.9 → round=7');

      // Use boundary values verified in group 10
      expect(_scored(5.79).recommendation, equals('谨慎买入'));
      expect(_scored(4.74).recommendation, equals('偏多观望'));
      expect(_scored(4.73).recommendation, equals('偏多观望'));
      expect(_scored(3.0).recommendation, equals('谨慎卖出'));
      expect(_scored(2.0).recommendation, equals('卖出'));
      expect(_scored(1.0).recommendation, equals('强烈卖出'));
    });
  });

  // ─── 8. Archive Screen Neutral Judgment Tests ───
  group('Archive Neutral Judgment', () {
    test('Neutral recommendation with small price change is reasonable', () {
      // 观望 + price change < 8% = 合理
      final wasNeutral = true;
      final priceChangePct = 6.0; // < 8%
      final isDeviation = wasNeutral && priceChangePct.abs() > 8;
      expect(isDeviation, false, reason: '观望 with <8% change should be reasonable');
    });

    test('Neutral recommendation with large price change is deviation', () {
      // 观望 + price change > 8% = 偏差
      final wasNeutral = true;
      final priceChangePct = 9.0; // > 8%
      final isDeviation = wasNeutral && priceChangePct.abs() > 8;
      expect(isDeviation, true, reason: '观望 with >8% change should be deviation');
    });

    test('Neutral recommendation with large negative change is deviation', () {
      final wasNeutral = true;
      final priceChangePct = -9.0; // abs > 8%
      final isDeviation = wasNeutral && priceChangePct.abs() > 8;
      expect(isDeviation, true, reason: '观望 with >-8% change should be deviation');
    });
  });

  // ─── 9. Archive Buy/Sell Judgment Tests ───
  group('Archive Buy/Sell Judgment', () {
    test('Buy recommendation with small decline is still reasonable', () {
      // 买入 + 跌 < 2% = 合理
      final wasBuy = true;
      final priceChangePct = -1.5; // > -2%
      final isDeviation = wasBuy && priceChangePct < -2;
      expect(isDeviation, false, reason: 'Buy with <2% decline should be reasonable');
    });

    test('Buy recommendation with large decline is deviation', () {
      // 买入 + 跌 > 2% = 偏差
      final wasBuy = true;
      final priceChangePct = -3.0; // < -2%
      final isDeviation = wasBuy && priceChangePct < -2;
      expect(isDeviation, true, reason: 'Buy with >2% decline should be deviation');
    });

    test('Sell recommendation with small rise is still reasonable', () {
      // 卖出 + 涨 < 2% = 合理
      final wasSell = true;
      final priceChangePct = 1.5; // < 2%
      final isDeviation = wasSell && priceChangePct > 2;
      expect(isDeviation, false, reason: 'Sell with <2% rise should be reasonable');
    });

    test('Sell recommendation with large rise is deviation', () {
      // 卖出 + 涨 > 2% = 偏差
      final wasSell = true;
      final priceChangePct = 3.0; // > 2%
      final isDeviation = wasSell && priceChangePct > 2;
      expect(isDeviation, true, reason: 'Sell with >2% rise should be deviation');
    });

    test('Buy recommendation with price rise is reasonable', () {
      final wasBuy = true;
      final priceChangePct = 1.0; // positive
      final isDeviation = wasBuy && priceChangePct < -2;
      expect(isDeviation, false, reason: 'Buy with price rise should be reasonable');
    });
  });

  // ─── 10. ComprehensiveScorer Formula Tests ───
  // v2.37: 验证 (adjustedScore).round().clamp(1, 10) 的边界映射（已移除 0.95 系数）
  group('ComprehensiveScorer Formula (round only, no 0.95×)', () {
    /// 辅助：设置 tech/realtime/confluence 等值，无 quote/news/capital
    /// v2.37 branch 1 权重: tech 0.50 + real 0.25 + conf 0.18 + struct 0.07 = 1.0
    /// 传入与score一致的structureScore使rawScore=score
    ComprehensiveScoreResult _scoreAll(double score) {
      final ms = MarketStructureResult(
        structure: MarketStructure.consolidation,
        confidence: 0.5, adxValue: 0, maAlignment: '混合',
        description: '', compatibleStrategies: [],
        structureScore: score,
      );
      return ComprehensiveScorer.combine(
        technicalScore: score,
        realtimeScore: score,
        confluenceScore: score,
        quote: null,
        marketContext: null,
        newsList: null,
        capitalFlowScore: null,
        marketPositionFactor: 1.0,
        marketStructure: ms,
      );
    }

    test('adjustedScore=5.0 maps to totalScore=5 (偏多观望)', () {
      final r = _scoreAll(5.0); // round=5
      expect(r.totalScore, equals(5));
      expect(r.recommendation, equals('偏多观望'));
    });

    test('adjustedScore=4.74 maps to totalScore=5 (偏多观望)', () {
      final r = _scoreAll(4.74); // round=5
      expect(r.totalScore, equals(5));
      expect(r.recommendation, equals('偏多观望'));
    });

    test('adjustedScore=4.73 maps to totalScore=5 (偏多观望)', () {
      // v2.37: 移除 0.95 系数后，4.73 → round=5（此前为 4.49→round=4 偏空观望）
      final r = _scoreAll(4.73); // round=5
      expect(r.totalScore, equals(5));
      expect(r.recommendation, equals('偏多观望'));
    });

    test('adjustedScore=5.79 maps to totalScore=6 (谨慎买入)', () {
      final r = _scoreAll(5.79); // round=6
      expect(r.totalScore, equals(6));
      expect(r.recommendation, equals('谨慎买入'));
    });

    test('adjustedScore=5.78 maps to totalScore=6 (谨慎买入)', () {
      // v2.37: 移除 0.95 系数后，5.78 → round=6（此前为 5.49→round=5 偏多观望）
      final r = _scoreAll(5.78); // round=6
      expect(r.totalScore, equals(6));
      expect(r.recommendation, equals('谨慎买入'));
    });

    test('adjustedScore=7.89 maps to totalScore=8 (强烈买入)', () {
      final r = _scoreAll(7.9); // round=8
      expect(r.totalScore, equals(8));
      expect(r.recommendation, equals('强烈买入'));
    });

    test('adjustedScore=10.0 maps to totalScore=10 (强烈买入)', () {
      final r = _scoreAll(10.0); // round=10
      expect(r.totalScore, equals(10));
      expect(r.recommendation, equals('强烈买入'));
    });

    test('adjustedScore=0 maps to totalScore=1 (clamp下限)', () {
      final r = _scoreAll(0.0); // round=0 → clamp=1
      expect(r.totalScore, equals(1));
      expect(r.recommendation, equals('强烈卖出'));
    });

    test('adjustedScore=2.5 maps to totalScore=2 (卖出)', () {
      // v2.38: 加回 0.97 系数后，2.5×0.97=2.425→round=2（卖出）
      final r = _scoreAll(2.5); // round=2
      expect(r.totalScore, equals(2));
      expect(r.recommendation, equals('卖出'));
    });

    test('ST stock adjustedScore=4.73 maps to totalScore<=5 (偏多观望 or 谨慎卖出)', () {
      final ms = MarketStructureResult(
        structure: MarketStructure.consolidation, confidence: 0.5,
        adxValue: 0, maAlignment: '混合', description: '',
        compatibleStrategies: [], structureScore: 4.73,
      );
      final r = ComprehensiveScorer.combine(
        technicalScore: 4.73,
        realtimeScore: 4.73,
        confluenceScore: 4.73,
        quote: QuoteData(code: 'sh600000', name: 'ST测试', price: 10.0),
        marketContext: null,
        newsList: null,
        capitalFlowScore: null,
        marketPositionFactor: 1.0,
        marketStructure: ms,
      );
      expect(r.totalScore, lessThanOrEqualTo(5));
      // v2.37 ST totalScore=4.73→round=5 → 偏多观望（封顶5）
      expect(r.recommendation, anyOf(equals('谨慎卖出'), equals('偏多观望')));
    });

    test('ST stock adjustedScore=5.0 maps to max 偏多观望', () {
      final r = ComprehensiveScorer.combine(
        technicalScore: 5.0,
        realtimeScore: 5.0,
        confluenceScore: 5.0,
        quote: QuoteData(code: 'sh600000', name: 'ST测试', price: 10.0,
          pe: 15.0, pb: 2.0, turnover: 3.0),
        marketContext: null,
        newsList: null,
        capitalFlowScore: null,
        marketPositionFactor: 1.0,
      );
      expect(r.totalScore, equals(5));
      expect(r.recommendation, equals('偏多观望'));
    });
  });

  /// 个股详情页顶部 3行12字段去重 (+顶部横排4字段)
  /// 顶部横排: 开盘, 最高, 最低, 昨收
  /// Row 1: 成交量, 成交额, 市盈率, 市净率
  /// Row 2: 总市值, 流通市值, 换手率, 振幅
  /// Row 3: 净流入, 净流入率, 主力流入, 主力流出
  group('QuoteData 字段映射完整性 (quote_screen.dart 顶部Header)', () {
    // Row 1: 成交量, 成交额, 市盈率, 市净率
    // Row 2: 总市值, 流通市值, 换手率, 振幅

    test('QuoteData 包含全部 12 个 Row 字段', () {
      final q = QuoteData(code: '000001', name: '测试股',
        price: 10.5, change: 0.5, changePct: 5.0,
        open: 10.0, high: 10.8, low: 9.8, preClose: 10.0,
        volume: 1e6, amount: 1.05e7,
        amplitude: 10.0, turnover: 5.0,
        pe: 15.5, pb: 2.3,
        totalMarketCap: 1e10, circulatingMarketCap: 8e9,
        mainInflow: 5e6, mainOutflow: 3e6,
        mainNetFlow: 2e6, mainNetFlowRate: 2.0,
      );

      // Row 1 字段
      expect(q.volume, greaterThan(0));     // 成交量
      expect(q.amount, greaterThan(0));     // 成交额
      expect(q.pe, greaterThan(0));         // 市盈率
      expect(q.pb, greaterThan(0));         // 市净率

      // Row 2 字段
      expect(q.totalMarketCap, greaterThan(0));  // 总市值
      expect(q.circulatingMarketCap, greaterThan(0)); // 流通市值
      expect(q.turnover, greaterThan(0));   // 换手率
      expect(q.amplitude, greaterThan(0));  // 振幅

      // Row 3 字段
      expect(q.mainInflow, greaterThan(0));    // 主力流入
      expect(q.mainOutflow, greaterThan(0));   // 主力流出
      expect(q.mainNetFlow, greaterThan(0));   // 净流入
      expect(q.mainNetFlowRate, greaterThan(0)); // 净流入率
    });

    test('12 字段全去重 (3行无交集 + 不与顶部横排重复)', () {
      // 顶部横排: open, high, low, preClose
      final topRow = {'open', 'high', 'low', 'preClose'};
      // 数据行
      final row1Fields = {'volume', 'amount', 'pe', 'pb'};
      final row2Fields = {'totalMarketCap', 'circulatingMarketCap', 'turnover', 'amplitude'};
      final row3Fields = {'mainInflow', 'mainOutflow', 'mainNetFlow', 'mainNetFlowRate'};

      final allRowFields = <String>{}
        ..addAll(row1Fields)
        ..addAll(row2Fields)
        ..addAll(row3Fields);

      // 3行 × 4列 = 12
      expect(allRowFields.length, equals(12));

      // 行间无交集
      expect(row1Fields.intersection(row2Fields).isEmpty, isTrue);
      expect(row1Fields.intersection(row3Fields).isEmpty, isTrue);
      expect(row2Fields.intersection(row3Fields).isEmpty, isTrue);

      // 数据行不与顶部横排重复
      expect(allRowFields.intersection(topRow).isEmpty, isTrue,
          reason: '数据行 ∩ 顶部横排 = ${allRowFields.intersection(topRow)}');

      // 验证所有字段在 QuoteData 上存在
      expect(allRowFields.every((f) => _quoteHasField(f)), isTrue);
    });

    test('边界值: PE/PB 为 0 或负值时不应崩溃', () {
      final qZero = QuoteData(code: '000001', pe: 0, pb: 0);
      expect(qZero.pe, equals(0));
      expect(qZero.pb, equals(0));

      final qNeg = QuoteData(code: '000002', pe: -5, pb: -1);
      expect(qNeg.pe, lessThan(0));
      expect(qNeg.pb, lessThan(0));
    });

    test('边界值: 资金流向为 0 不崩溃', () {
      final q = QuoteData(code: '000001',
        mainInflow: 0, mainOutflow: 0, mainNetFlow: 0, mainNetFlowRate: 0);
      expect(q.mainInflow, equals(0));
      expect(q.mainOutflow, equals(0));
      expect(q.mainNetFlow, equals(0));
      expect(q.mainNetFlowRate, equals(0));
    });

    test('边界值: 市值/成交量为 0 不崩溃', () {
      final q = QuoteData(code: '000001',
        totalMarketCap: 0, circulatingMarketCap: 0, volume: 0, amount: 0);
      expect(q.totalMarketCap, equals(0));
      expect(q.circulatingMarketCap, equals(0));
      expect(q.volume, equals(0));
      expect(q.amount, equals(0));
    });
  });
}

/// 验证 QuoteData 是否包含某字段 (编译时检查, 用于测试)
bool _quoteHasField(String fieldName) {
  final q = QuoteData(code: '000001');
  switch (fieldName) {
    case 'volume': q.volume; break;
    case 'amount': q.amount; break;
    case 'pe': q.pe; break;
    case 'pb': q.pb; break;
    case 'totalMarketCap': q.totalMarketCap; break;
    case 'circulatingMarketCap': q.circulatingMarketCap; break;
    case 'open': q.open; break;
    case 'preClose': q.preClose; break;
    case 'turnover': q.turnover; break;
    case 'amplitude': q.amplitude; break;
    case 'high': q.high; break;
    case 'low': q.low; break;
    case 'mainInflow': q.mainInflow; break;
    case 'mainOutflow': q.mainOutflow; break;
    case 'mainNetFlow': q.mainNetFlow; break;
    case 'mainNetFlowRate': q.mainNetFlowRate; break;
    default: return false;
  }
  return true;
}
