import '../models/stock_models.dart';
import 'indicators.dart';
import 'signal_layer.dart';
import 'technical_scorer.dart';
import 'realtime_scorer.dart';
import 'confluence_scorer.dart';
import 'comprehensive_scorer.dart';
import 'risk_analyzer.dart';
import 'opportunity_identifier.dart';
import 'suggestion_generator.dart';
import 'confidence_calculator.dart';
import 'strategy_builder.dart';
import 'strategy_engine.dart';
import 'backtest_engine.dart';
import 'sr_quality.dart';

/// 向后兼容：检测特有信号（量价背离、布林收口）
List<SignalItem> detectSignals(List<HistoryKline> data) {
  return SignalLayer.detectUniqueSignals(data);
}

/// 计算交易价位
Map<String, dynamic> calcTradeLevels(List<HistoryKline> data) {
  if (data.isEmpty) return {};

  final last = data[data.length - 1];
  final price = last.close;

  final supportLevels = calcSupportResistance(data);
  final supports = supportLevels['support'] as List<double>? ?? [];
  final resistances = supportLevels['resistance'] as List<double>? ?? [];

  final nearestSupport = supports.isNotEmpty ? supports.first : null;
  final nearestResistance = resistances.isNotEmpty ? resistances.first : null;

  final entryLow = nearestSupport ?? price * 0.98;
  final entryHigh = price * 1.01;
  final target = nearestResistance ?? price * 1.1;
  final stopLoss = last.ma60 > 0
      ? [entryLow * 0.98, last.ma60 * 0.97].reduce((a, b) => a < b ? a : b)
      : entryLow * 0.98;

  final entryMid = (entryLow + entryHigh) / 2;
  final reward = target - entryMid;
  final risk = entryMid - stopLoss;
  final riskRewardRatio = risk > 0 ? reward / risk : 0.0;

  final support = nearestSupport ?? 0;
  final support2 = supports.length > 1 ? supports[1] : 0.0;
  final resistance = nearestResistance ?? 0;
  final resistance2 = resistances.length > 1 ? resistances[1] : 0.0;

  final tradeLevels = <String, dynamic>{
    'entry_low': entryLow,
    'entry_high': entryHigh,
    'target': target,
    'stop_loss': stopLoss,
    'risk_reward_ratio': riskRewardRatio,
    'has_support': nearestSupport != null,
    'has_resistance': nearestResistance != null,
  };

  // 支撑压力位质量评估
  if (data.length >= 30) {
    final supportsList = [support, support2].where((s) => s > 0).toList();
    final resistancesList = [resistance, resistance2].where((r) => r > 0).toList();
    for (int i = 0; i < supportsList.length; i++) {
      final quality = SRQualityEvaluator.evaluateSupport(data, supportsList[i]);
      tradeLevels.addAll({
        'support_${i + 1}_quality': quality.quality,
        'support_${i + 1}_test_count': quality.testCount,
        'support_${i + 1}_reliability': quality.reliability,
      });
    }
    for (int i = 0; i < resistancesList.length; i++) {
      final quality = SRQualityEvaluator.evaluateResistance(data, resistancesList[i]);
      tradeLevels.addAll({
        'resistance_${i + 1}_quality': quality.quality,
        'resistance_${i + 1}_test_count': quality.testCount,
        'resistance_${i + 1}_reliability': quality.reliability,
      });
    }
  }
  return tradeLevels;
}

/// 生成分析结果（薄编排器）
AnalysisResult generateAnalysis(
  List<HistoryKline> data,
  QuoteData? quote, {
  MarketContext? marketContext,
  List<dynamic>? newsList,
}) {
  if (data.isEmpty) {
    return AnalysisResult(
      signals: [],
      indicators: {},
      recommendation: '观望',
      score: 5,
      riskLevel: '中等',
      riskFactors: ['数据不足'],
      suggestions: ['等待更多数据'],
      reasons: ['数据不足，无法生成有效建议'],
      opportunities: [],
      confidenceScore: 0.3,
    );
  }

  final last = data[data.length - 1];

  // 1. 信号检测
  final signals = SignalLayer.detectAllSignals(data);
  final indicators = getIndicatorSummary(data);

  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  // 2. 技术面评分
  final techResult = TechnicalScorer.score(data, buySignals, sellSignals);

  // 3. 实时行情评分
  final realtimeScore = RealtimeScorer.score(quote);

  // 4. 共振评分
  final confluenceResult = ConfluenceScorer.score(last, signals);

  // 5. 综合评分
  final compResult = ComprehensiveScorer.combine(
    technicalScore: techResult.totalScore,
    realtimeScore: realtimeScore,
    confluenceScore: confluenceResult.score,
    quote: quote,
    marketContext: marketContext,
    newsList: newsList,
  );

  final totalScore = compResult.totalScore;
  final recommendation = compResult.recommendation;

  // 6. 推荐理由
  final reasons = _generateReasons(buySignals, sellSignals, last, quote);

  // 7. 风险分析
  final riskResult = RiskAnalyzer.analyze(data, last, quote);

  // 8. 机会识别
  final opportunities = OpportunityIdentifier.identify(buySignals);

  // 9. 操作建议
  final suggestions = SuggestionGenerator.generate(
    recommendation: recommendation,
    data: data,
    last: last,
    quote: quote,
    buySignals: buySignals,
    sellSignals: sellSignals,
    totalScore: totalScore,
  );

  // 10. 回测统计
  Map<String, BacktestResult> backtestResults = {};
  try {
    if (data.length >= 60) {
      backtestResults['MACD金叉'] = BacktestEngine.backtestMACDCross(data);
      backtestResults['MA金叉'] = BacktestEngine.backtestMACross(data);
      backtestResults['KDJ超卖'] = BacktestEngine.backtestKDJOversoldCross(data);
      backtestResults['RSI超卖'] = BacktestEngine.backtestRSIOversoldRecovery(data);
    }
  } catch (_) {
    backtestResults = {};
  }

  // 11. 分层策略
  List<TradingStrategy> shortTermStrategies = [];
  List<TradingStrategy> longTermStrategies = [];
  try {
    shortTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.shortTerm);
    longTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.longTerm);
  } catch (_) {}

  // 12. 置信度计算（内部已包含对抗验证）
  final confResult = ConfidenceCalculator.calculate(
    buySignals: buySignals,
    sellSignals: sellSignals,
    signals: signals,
    totalScore: totalScore,
    last: last,
    quote: quote,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
  );
  final confidenceScore = confResult.confidenceScore;
  final validatedSignals = confResult.validatedSignals;
  final confidenceBreakdown = ConfidenceCalculator.breakdown(
    buySignals: buySignals,
    sellSignals: sellSignals,
    totalScore: totalScore,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
  );

  // 13. 详细推荐理由
  final detailedReasons = <RecommendationReason>[];
  for (final signal in signals.take(5)) {
    if (signal.confidence != null) {
      detailedReasons.add(RecommendationReason(
        title: signal.signal,
        description: signal.description,
        confidence: signal.confidence!,
        duration: signal.duration == SignalDuration.shortTerm ? '短期' : signal.duration == SignalDuration.mediumTerm ? '中期' : '长期',
      ));
    }
  }
  if (marketContext != null) {
    detailedReasons.add(RecommendationReason(
      title: '市场环境',
      description: '上证${marketContext.shIndexPct.toStringAsFixed(2)}%，深证${marketContext.szIndexPct.toStringAsFixed(2)}%',
      confidence: 0.7,
      duration: '环境',
    ));
  }

  final tradeLevels = calcTradeLevels(data);

  return AnalysisResult(
    signals: signals,
    indicators: indicators,
    recommendation: recommendation,
    score: totalScore,
    riskLevel: riskResult.riskLevel,
    riskFactors: riskResult.riskFactors,
    suggestions: suggestions,
    tradeLevels: tradeLevels.isNotEmpty ? tradeLevels : null,
    confluenceScore: confluenceResult.score.round(),
    confluenceDetails: confluenceResult.details,
    reasons: reasons,
    opportunities: opportunities,
    shortTermStrategies: shortTermStrategies,
    longTermStrategies: longTermStrategies,
    marketContext: marketContext,
    confidenceScore: confidenceScore,
    detailedReasons: detailedReasons,
    backtestResults: backtestResults,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    validatedSignals: validatedSignals,
    confidenceBreakdown: confidenceBreakdown,
  );
}

/// 生成推荐理由
List<String> _generateReasons(
  List<SignalItem> buySignals,
  List<SignalItem> sellSignals,
  HistoryKline last,
  QuoteData? quote,
) {
  final reasons = <String>[];
  final buyCount = buySignals.length;
  final sellCount = sellSignals.length;

  if (buyCount > sellCount + 1) reasons.add('多个买入信号共振');
  if (sellCount > buyCount + 1) reasons.add('多个卖出信号共振');
  if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma5 > 0) reasons.add('均线多头排列');
  if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma5 > 0) reasons.add('均线空头排列');
  if (last.rsi6 > 70) reasons.add('RSI超买区域');
  if (last.rsi6 < 30 && last.rsi6 > 0) reasons.add('RSI超卖区域');
  if (last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) reasons.add('成交量显著放大');
  if (last.close >= last.open && last.volume < last.volMa5 * 0.7 && last.volMa5 > 0) reasons.add('上涨缩量，动能不足');

  if (quote != null && quote.price > 0) {
    if (quote.changePct > 3) reasons.add('当日涨幅${quote.changePct.toStringAsFixed(1)}%，追高需谨慎');
    if (quote.changePct < -3) reasons.add('当日跌幅${quote.changePct.toStringAsFixed(1)}%，短线偏弱');
    if (quote.mainNetFlow > 0 && quote.mainNetFlowRate > 3) reasons.add('主力资金净流入${quote.mainNetFlowRate.toStringAsFixed(1)}%');
    if (quote.mainNetFlow < 0 && quote.mainNetFlowRate < -3) reasons.add('主力资金净流出${quote.mainNetFlowRate.abs().toStringAsFixed(1)}%');
    if (quote.turnover > 10) reasons.add('换手率${quote.turnover.toStringAsFixed(1)}%，交投过热');
  }

  return reasons;
}
