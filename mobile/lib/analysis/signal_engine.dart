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
import 'capital_flow_analyzer.dart';
import 'market_structure_analyzer.dart';
import 'percentile_analyzer.dart';

/// 向后兼容：检测特有信号（量价背离、布林收口）
List<SignalItem> detectSignals(List<HistoryKline> data) {
  return SignalLayer.detectUniqueSignals(data);
}

/// 计算交易价位（v2.25: ATR动态止损 + 追踪止损 + 分级止盈）
Map<String, dynamic> calcTradeLevels(List<HistoryKline> data) {
  if (data.isEmpty) return {};

  final last = data[data.length - 1];
  final price = last.close;
  final atr = last.atr14 > 0 ? last.atr14 : price * 0.03;

  final supportLevels = calcSupportResistance(data);
  final supports = supportLevels['support'] as List<double>? ?? [];
  final resistances = supportLevels['resistance'] as List<double>? ?? [];

  final nearestSupport = supports.isNotEmpty ? supports.first : null;
  final nearestResistance = resistances.isNotEmpty ? resistances.first : null;

  // ATR动态入场区间
  // 入场低: 最近支撑或价格-1.5倍ATR（取更保守的）
  final rawEntryLow = nearestSupport ?? (price - atr * 1.5);
  final entryLow = (rawEntryLow > price * 0.95 ? rawEntryLow : price * 0.95);

  // ATR动态止损：2倍ATR或最近20日最低点，取更紧的
  // 底线: 止损必须低于入场价
  double atrStopLoss = entryLow - atr * 2.0;
  if (data.length >= 20) {
    final recent20Low = data.sublist(data.length - 20).map((d) => d.low).reduce(
        (a, b) => a < b ? a : b);
    final swingStop = recent20Low * 0.995;
    if (swingStop > atrStopLoss && swingStop < entryLow * 0.98) {
      atrStopLoss = swingStop;
    }
  }
  // MA60长线防线: 仅当MA60在入场价下方时才能作为止损参考
  if (last.ma60 > 0 && last.ma60 > atrStopLoss && last.ma60 < entryLow) {
    atrStopLoss = last.ma60;
  }
  final stopLoss = atrStopLoss.clamp(0.0, entryLow * 0.99);

  // 分级止盈目标（基于 entryLow → stopLoss 的风险）
  final riskAmount = (entryLow - stopLoss).clamp(entryLow * 0.005, double.infinity);
  final tp1 = (entryLow + riskAmount * 1.5).clamp(entryLow * 1.01, double.infinity);
  final rawTp2 = (nearestResistance != null && nearestResistance > tp1)
      ? nearestResistance : (entryLow + riskAmount * 2.5);
  final tp2 = rawTp2.clamp(tp1 * 1.01, double.infinity);
  final rawTp3 = (last.bollUpper > 0 && last.bollUpper > tp2)
      ? last.bollUpper : (entryLow + riskAmount * 3.5);
  final tp3 = rawTp3.clamp(tp2 * 1.01, double.infinity);

  // 入场高: 价格+0.5倍ATR，entryLow < entryHigh < tp1 (不得高于tp1)
  final rawEntryHigh = price + atr * 0.5;
  final eHighLower = entryLow * 1.001;
  final eHighUpper = tp1 * 0.98;
  final entryHigh = eHighLower < eHighUpper
      ? rawEntryHigh.clamp(eHighLower, eHighUpper)
      : entryLow * 1.001; // 极小利润空间时退回最低入场高
  final target = tp2; // 主目标设为TP2

  // 追踪止损相关参数（供前端UI展示）
  final trailingStopActivation = price + atr * 2.0; // 盈利2×ATR后启动追踪
  final trailingStopDistance = atr * 1.5; // 追踪止损距离

  final entryMid = (entryLow + entryHigh) / 2;
  final reward = (target - entryMid).clamp(0.0, double.infinity);
  final risk = (entryMid - stopLoss).clamp(0.0, double.infinity);
  final riskRewardRatio = risk > 0 ? reward / risk : 0.0;

  // ── 保序断言: 止损 < 入场低 < 止盈1 < 止盈2 < 止盈3 ──
  assert(stopLoss <= entryLow, 'stopLoss=$stopLoss > entryLow=$entryLow');
  assert(entryLow <= tp1, 'entryLow=$entryLow > tp1=$tp1');
  assert(tp1 <= tp2, 'tp1=$tp1 > tp2=$tp2');
  assert(tp2 <= tp3, 'tp2=$tp2 > tp3=$tp3');

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
    // 新增：分级止盈
    'tp1': tp1,
    'tp2': tp2,
    'tp3': tp3,
    // 新增：追踪止损参数
    'trailing_stop_activation': trailingStopActivation,
    'trailing_stop_distance': trailingStopDistance,
    // 新增：ATR参考值
    'atr': atr,
    'atr_stop_width': atr * 2.0,
    // 新增：风险金额（基于入场低和止损）
    'risk_per_share': (entryLow - stopLoss).abs(),
    'risk_pct': entryLow > 0
        ? ((entryLow - stopLoss) / entryLow * 100).abs().toStringAsFixed(2)
        : '0.00',
    // 新增：止损类型描述
    'stop_loss_type': _getStopLossType(data, last, atrStopLoss),
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

/// 判断止损类型
String _getStopLossType(List<HistoryKline> data, HistoryKline last, double stopPrice) {
  if (last.ma60 > 0 && (stopPrice - last.ma60).abs() < last.ma60 * 0.005) {
    return '均线止损(MA60)';
  }
  if (data.length >= 20) {
    final recent20Low = data.sublist(data.length - 20).map((d) => d.low).reduce(
        (a, b) => a < b ? a : b);
    if ((stopPrice - recent20Low * 0.995).abs() < recent20Low * 0.003) {
      return '20日低点止损';
    }
  }
  return 'ATR动态止损(${(last.atr14 / last.close * 100).toStringAsFixed(1)}%)';
}

/// 信号名 → 回测策略名映射（匹配 backtest_engine 的 key）
/// 返回 null 表示该信号类型暂无对应回测策略，不参与置信度调整
/// 卖出信号通过 2.0-adj 反向映射：回测表现越好 → 买入置信度越低
String? mapSignalToBacktestKey(String signalName) {
  const map = {
    // ── 买入类：回测表现好 → 提升置信度 ──
    'MACD金叉': 'MACD交叉',
    'MACD零轴上方金叉': 'MACD交叉',
    'MACD底背离': 'MACD交叉',
    'MA5上穿MA10': 'MA金叉',
    'MA10上穿MA20': 'MA金叉',
    'KDJ金叉': 'KDJ超卖',
    'RSI超卖回升': 'RSI超卖',
    '跌破下轨': '布林支撑',
    '均线多头排列': '均线多头',

    // ── 卖出类：回测表现好 → 降低信心（应用 2.0-adj 反向） ──
    'MACD死叉': 'MACD交叉',
    'MACD顶背离': 'MACD交叉',
    'MA5下穿MA10': 'MA金叉',
    'MA10下穿MA20': 'MA金叉',
    'KDJ死叉': 'KDJ超卖',
    'RSI超买回落': 'RSI超卖',
    '均线空头排列': '均线多头',

    // ── 暂无回测映射（保留 null 显式标记） ──
    '放量上涨': null,
    'WR超卖': null,
    'OBV放量上涨': null,
    'CCI超卖回升': null,
    '向上跳空突破': null,
    '底部锤子线': null,
    '刺透形态': null,
    '阳包阴': null,
    '低位十字星': null,
    '三阳开泰': null,
    '启明星': null,
    '主力吸筹迹象': null,
    '地量见底': null,
    '趋势突破上轨': null,
    'WR超买': null,
    'CCI超买回落': null,
    '缩量上涨': null,
    '向下跳空破位': null,
    '顶部吊颈线': null,
    '乌云盖顶': null,
    '阴包阳': null,
    '高位十字星': null,
    '三只乌鸦': null,
    '黄昏星': null,
    '主力派发迹象': null,
    '趋势强度强劲': null,
    '盘整趋势': null,
  };
  return map[signalName];
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

  // 1a. 市场结构分析 (Phase 1)
  final marketStructure = MarketStructureAnalyzer.analyze(data);

  // 1b. 分位值分析 (Phase 4)
  final percentile = PercentileAnalyzer.analyze(data, quote);

  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  // 2. 技术面评分
  final techResult = TechnicalScorer.score(data, buySignals, sellSignals);

  // 3. 实时行情评分
  final realtimeScore = RealtimeScorer.score(quote);

  // 4. 共振评分
  final confluenceResult = ConfluenceScorer.score(last, signals);

  // 4a. 资金流向分析
  double? capitalFlowScore;
  try {
    final flowResult = CapitalFlowAnalyzer.analyze(klineData: data, quote: quote);
    capitalFlowScore = flowResult.score;
  } catch (_) {}

  // 5. 综合评分
  final compResult = ComprehensiveScorer.combine(
    technicalScore: techResult.totalScore,
    realtimeScore: realtimeScore,
    confluenceScore: confluenceResult.score,
    capitalFlowScore: capitalFlowScore,
    quote: quote,
    marketContext: marketContext,
    newsList: newsList,
    marketStructure: marketStructure,
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

  // 10. 全策略回测 + 反馈闭环
  Map<String, BacktestResult> backtestResults = {};
  String backtestSummary = '';
  if (data.length >= 60) {
    try {
      backtestResults = BacktestEngine.megaBacktest(data);
      backtestSummary = BacktestEngine.getBacktestSummary(backtestResults);
    } catch (_) {}
  }

  // 11. 分层策略
  List<TradingStrategy> shortTermStrategies = [];
  List<TradingStrategy> longTermStrategies = [];
  try {
    shortTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.shortTerm);
    longTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.longTerm);
    // Phase 1: 根据市场结构禁用不兼容策略
    final incompatibleNames = getIncompatibleStrategies(marketStructure.structure);
    for (final s in shortTermStrategies) {
      if (incompatibleNames.contains(s.name)) s.isActive = false;
    }
    for (final s in longTermStrategies) {
      if (incompatibleNames.contains(s.name)) s.isActive = false;
    }
  } catch (e) { debugPrint('SignalEngine.structureFilter: $e'); }

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
    marketStructure: marketStructure,
  );
  // 回测反馈闭环：根据策略历史表现调整置信度
  double confidenceScore = confResult.confidenceScore;
  if (backtestResults.isNotEmpty) {
    final adjustments = <double>[];
    // 买入信号：回测表现好 → 提升置信度
    for (final signal in buySignals) {
      final strategyName = mapSignalToBacktestKey(signal.signal);
      if (strategyName != null) {
        final adj = BacktestEngine.getStrategyConfidenceAdjustment(
          strategyName, backtestResults);
        adjustments.add(adj);
      }
    }
    // 卖出信号：回测表现好 → 降低置信度（反向确认）
    for (final signal in sellSignals) {
      final strategyName = mapSignalToBacktestKey(signal.signal);
      if (strategyName != null) {
        final adj = BacktestEngine.getStrategyConfidenceAdjustment(
          strategyName, backtestResults);
        // 卖出信号可靠性高 → 买入置信度应降低
        adjustments.add(2.0 - adj); // adj 1.0 → 1.0, adj 1.3 → 0.7, adj 0.7 → 1.3
      }
    }
    if (adjustments.isNotEmpty) {
      final avgAdjustment = adjustments.reduce((a, b) => a + b) / adjustments.length;
      confidenceScore = (confidenceScore * (0.5 + avgAdjustment * 0.5)).clamp(0.2, 0.95);
    }
  }
  final validatedSignals = confResult.validatedSignals;
  final confidenceBreakdown = ConfidenceCalculator.breakdown(
    buySignals: buySignals,
    sellSignals: sellSignals,
    totalScore: totalScore,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
    marketStructure: marketStructure,
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
    backtestSummary: backtestSummary.isEmpty ? null : backtestSummary,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    validatedSignals: validatedSignals,
    confidenceBreakdown: confidenceBreakdown,
    marketStructure: marketStructure,
    percentile: percentile,
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
