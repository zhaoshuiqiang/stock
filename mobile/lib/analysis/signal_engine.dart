import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import '../core/ai_config.dart';
import 'indicators.dart';
import 'signal_layer.dart';
import 'technical_scorer.dart';
import 'realtime_scorer.dart';
import 'confluence_scorer.dart';
import 'comprehensive_scorer.dart';
import 'sector_momentum_calculator.dart';
import 'risk_analyzer.dart';
import 'opportunity_identifier.dart';
import 'suggestion_generator.dart';
import 'confidence_calculator.dart';
import 'strategy_builder.dart';
import 'strategy_engine.dart';
import 'backtest_engine.dart';
import 'limit_up_analyzer.dart';
import 'sr_quality.dart';
import 'capital_flow_analyzer.dart';
import 'market_structure_analyzer.dart';
import 'percentile_analyzer.dart';
import 'ai_layer.dart';
import 'debate_engine.dart';
import 'recommendation_tracker.dart';
import 'recommendation_explainer.dart';
import 'pattern_recognizer.dart';
import 'sector_rotation.dart';
import 'momentum_persistence_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import 'next_session_predictor.dart';
import 'signal_detector.dart';
import 'short_term_decision_engine.dart';
import 'short_term_direction_model.dart';
import 'intraday_analyzer.dart';
import 'structure_transition_detector.dart';

/// 向后兼容：检测特有信号（量价背离、布林收口）
List<SignalItem> detectSignals(List<HistoryKline> data) {
  return SignalLayer.detectUniqueSignals(data);
}

double _componentToScore(double component) {
  return ((component + 1) / 2 * 10).clamp(0.0, 10.0);
}

double _predictionSupportForRecommendation(
  RecommendationDirection direction,
  NextDayPredictionResult prediction,
) {
  if (direction == RecommendationDirection.bullish) {
    return prediction.upProbability.clamp(0.0, 1.0).toDouble();
  }
  if (direction == RecommendationDirection.bearish) {
    return prediction.downProbability.clamp(0.0, 1.0).toDouble();
  }
  final neutralSupport =
      prediction.neutralProbability.clamp(0.0, 1.0).toDouble();
  if (prediction.sampleCount < NextDayPredictor.minSampleSize) {
    return neutralSupport;
  }
  final balanceSupport =
      1.0 - (prediction.upProbability - prediction.downProbability).abs();
  return (neutralSupport * 0.7 + balanceSupport * 0.3)
      .clamp(0.0, 1.0)
      .toDouble();
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
    final recent20Low = data
        .sublist(data.length - 20)
        .map((d) => d.low)
        .reduce((a, b) => a < b ? a : b);
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
  final riskAmount =
      (entryLow - stopLoss).clamp(entryLow * 0.005, double.infinity);
  final tp1 =
      (entryLow + riskAmount * 1.5).clamp(entryLow * 1.01, double.infinity);
  final rawTp2 = (nearestResistance != null && nearestResistance > tp1)
      ? nearestResistance
      : (entryLow + riskAmount * 2.5);
  final tp2 = rawTp2.clamp(tp1 * 1.01, double.infinity);
  final rawTp3 = (last.bollUpper > 0 && last.bollUpper > tp2)
      ? last.bollUpper
      : (entryLow + riskAmount * 3.5);
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
    final resistancesList =
        [resistance, resistance2].where((r) => r > 0).toList();
    for (int i = 0; i < supportsList.length; i++) {
      final quality = SRQualityEvaluator.evaluateSupport(data, supportsList[i]);
      tradeLevels.addAll({
        'support_${i + 1}_quality': quality.quality,
        'support_${i + 1}_test_count': quality.testCount,
        'support_${i + 1}_reliability': quality.reliability,
      });
    }
    for (int i = 0; i < resistancesList.length; i++) {
      final quality =
          SRQualityEvaluator.evaluateResistance(data, resistancesList[i]);
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
String _getStopLossType(
    List<HistoryKline> data, HistoryKline last, double stopPrice) {
  if (last.ma60 > 0 && (stopPrice - last.ma60).abs() < last.ma60 * 0.005) {
    return '均线止损(MA60)';
  }
  if (data.length >= 20) {
    final recent20Low = data
        .sublist(data.length - 20)
        .map((d) => d.low)
        .reduce((a, b) => a < b ? a : b);
    if ((stopPrice - recent20Low * 0.995).abs() < recent20Low * 0.003) {
      return '20日低点止损';
    }
  }
  if (last.close > 0 && last.atr14 > 0) {
    return 'ATR动态止损(${(last.atr14 / last.close * 100).toStringAsFixed(1)}%)';
  }
  return 'ATR动态止损';
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
    // 注意：'KDJ金叉' 信号涵盖所有金叉，但回测 'KDJ超卖' 仅测试 K<30 的金叉。
    // 样本不完全匹配，回测反馈可能高估普通金叉的可靠性。
    // 保留映射因 KDJ 超卖金叉回测表现对 KDJ 金叉类信号仍有参考价值。
    'KDJ金叉': 'KDJ超卖',
    'RSI超卖回升': 'RSI超卖',
    '跌破下轨': '布林支撑',
    '均线多头排列': '均线多头',

    // ── 卖出类：回测表现好 → 降低信心（应用 2.0-adj 反向） ──
    'MACD死叉': 'MACD交叉',
    'MACD顶背离': 'MACD交叉',
    'MA5下穿MA10': 'MA金叉',
    'MA10下穿MA20': 'MA金叉',
    // 'KDJ死叉' 不映射：回测 'KDJ超卖' 是买入策略（K<30 金叉买入），
    // 与 KDJ 死叉卖出信号（K>50 死叉）样本不匹配，映射会引入噪声。
    'RSI超买回落': 'RSI超卖',
    '均线空头排列': '均线多头',

    // ── 暂无回测映射（保留 null 显式标记） ──
    '放量上涨': null,
    'WR超卖': 'WR超卖',
    'OBV放量上涨': null,
    'CCI超卖回升': 'CCI超卖',
    '向上跳空突破': '向上跳空',
    '底部锤子线': '锤子线反转',
    '刺透形态': '刺透形态',
    '阳包阴': '阳包阴',
    '低位十字星': '十字星反转',
    '三阳开泰': null,
    '启明星': '启明星',
    '主力吸筹迹象': null,
    '地量见底': null,
    '趋势突破上轨': null,
    'WR超买': 'WR超卖',
    'CCI超买回落': 'CCI超卖',
    '缩量上涨': null,
    '向下跳空破位': '向下跳空回补',
    '顶部吊颈线': '锤子线反转',
    '乌云盖顶': '乌云盖顶',
    '阴包阳': '阴包阳',
    '高位十字星': '十字星反转',
    '三只乌鸦': null,
    '黄昏星': '黄昏星',
    '主力派发迹象': null,
    '趋势强度强劲': null,
    '盘整趋势': null,
  };
  return map[signalName];
}

/// 生成分析结果（薄编排器）
/// [onAIUpdate] - AI分析完成后的回调，用于UI刷新
/// [onAIProgress] - AI分析进度回调
/// [autoTriggerAI] - 是否自动触发AI分析（默认false，改为手动触发）
AnalysisResult generateAnalysis(
  List<HistoryKline> data,
  QuoteData? quote, {
  MarketContext? marketContext,
  List<dynamic>? newsList,
  String? sectorName,
  List<SectorAnalysis>? sectorAnalysis,
  void Function(List<String> aiReasons)? onAIUpdate,
  void Function(String status, int progress)? onAIProgress,
  bool autoTriggerAI = false,
  bool enableAsyncSideEffects = true,
  IntradayProfile? intradayProfile,
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

  // v3.19: 防御性不变量——若调用方未预计算指标（如直接喂入缓存 JSON K 线），
  // 则在此强制重算，避免所有指标停在默认值导致信号静默失效或误触发（见代码评审 1.2）。
  if (data.length > 20 &&
      data.last.rsi6 == 0 &&
      data.last.macdHist == 0 &&
      data.last.adx14 == 0) {
    data = calcAllIndicators(data);
  }

  final last = data[data.length - 1];

  // 1. 信号检测
  final signals = SignalLayer.detectAllSignals(data);
  final indicators = getIndicatorSummary(data);

  // 1d. 预警信号检测（提前1-2天）
  final earlyWarningSignals = SignalDetector.detectEarlyWarningSignals(data);
  signals.addAll(earlyWarningSignals);

  // v2.30: 经典形态识别（双底/头肩底/三角突破）
  if (data.length >= 30) {
    try {
      final patternSignals = PatternRecognizer.detectAll(data);
      for (final p in patternSignals) {
        signals.add(SignalItem(
          type: p.direction == 'bullish' ? 'buy' : 'sell',
          indicator: '形态',
          signal: p.patternName,
          description: p.description,
          strength: (p.confidence * 100).round().clamp(45, 90).toInt(),
          duration: SignalDuration.mediumTerm,
          confidence: p.confidence,
        ));
      }
    } catch (e) {
      debugPrint('[信号引擎] PatternRecognizer 失败: $e');
    }
  }

  // 1a. 市场结构分析 (Phase 1)
  final marketStructure = MarketStructureAnalyzer.analyze(data);

  // 1a+. 结构转换检测
  StructureTransition? structureTransition;
  if (quote != null) {
    try {
      structureTransition = StructureTransitionDetector.detect(
        quote.code, data, marketStructure,
      );
    } catch (e) {
      debugPrint('[信号引擎] 结构转换检测失败: $e');
    }
  }

  // 1b. 分位值分析 (Phase 4)
  final percentile = PercentileAnalyzer.analyze(data, quote);

  // 1c. 打板分析 (激活 LimitUpAnalyzer 孤儿模块)
  // 从日K线推断涨停/连板信息，识别打板标的（非涨停返回 null）
  final limitUpAnalysis = quote != null
      ? LimitUpAnalyzer.analyzeFromDaily(
          code: quote.code,
          name: quote.name,
          klines: data,
          quote: quote,
        )
      : null;

  // 1e. 动量持续性分析（新增）
  final momentumPersistence = MomentumPersistenceAnalyzer.analyze(data);

  // 1f. 次日涨跌概率预测（新增）
  final nextSessionPrediction = NextSessionPredictor.predict(data);
  final nextDayPrediction = NextDayPredictionResult(
    upProbability: nextSessionPrediction.nextCloseUpProbability,
    downProbability: nextSessionPrediction.downsideRiskProbability,
    neutralProbability: nextSessionPrediction.neutralProbability,
    sampleCount: nextSessionPrediction.sampleCount,
    description: '基于K近邻合并预测',
    featureBins: data.isNotEmpty
        ? NextDayPredictor.extractFeatureBinsPublic(data.last)
        : {},
  );

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
    final flowResult =
        CapitalFlowAnalyzer.analyze(klineData: data, quote: quote);
    capitalFlowScore = flowResult.score;
  } catch (e) {
    debugPrint('[信号引擎] CapitalFlowAnalyzer 失败: $e');
  }

  // 5. 综合评分 (v2.38: 传递 sectorName/sectorAnalysis 用于板块情绪过热检测)
  final effectiveSectorName = sectorName ?? quote?.sectorName;
  SectorMomentumResult? sectorMomentumResult;
  if (effectiveSectorName != null && sectorAnalysis != null && sectorAnalysis.isNotEmpty) {
    sectorMomentumResult = SectorMomentumCalculator.calculate(
      sectorName: effectiveSectorName,
      sectorAnalysis: sectorAnalysis,
      stockChangePct: quote?.changePct ?? 0,
    );
  }
  final compResult = ComprehensiveScorer.combine(
    technicalScore: techResult.totalScore,
    realtimeScore: realtimeScore,
    confluenceScore: confluenceResult.score,
    capitalFlowScore: capitalFlowScore,
    quote: quote,
    marketContext: marketContext,
    newsList: newsList,
    marketStructure: marketStructure,
    currentChangePct: quote?.changePct,
    bias6: last.bias6,
    data: data,
    adxValue: marketStructure.adxValue,
    isBullAlign: marketStructure.maAlignment == '多头',
    industryRSScore: percentile.industryRSScore,
    sectorName: effectiveSectorName,
    sectorAnalysis: sectorAnalysis,
    intradayProfile: intradayProfile,
    nextDayPrediction: nextDayPrediction,
    nextSessionPrediction: nextSessionPrediction,
    sectorMomentum: sectorMomentumResult,
  );

  // 6. 推荐理由（见下方步骤13，全部上下文就绪后生成）

  // 7. 风险分析
  final riskResult = RiskAnalyzer.analyze(data, last, quote);

  // 8. 机会识别
  final opportunities = OpportunityIdentifier.identify(buySignals);

  // 8a. 交易价位（提前计算，供机会评分使用）
  final tradeLevels = calcTradeLevels(data);

  // 8b. 机会评分（5维评估+信号协同）
  final opportunityScore = OpportunityIdentifier.evaluate(
    buySignals: buySignals,
    sellSignals: sellSignals,
    klineData: data,
    quote: quote,
    marketStructure: marketStructure,
    marketContext: marketContext,
    riskRewardRatio: tradeLevels['risk_reward_ratio'] as double?,
  );

  // 9. 操作建议（见下方，全部上下文就绪后生成）

  // 10. 全策略回测 + 反馈闭环
  Map<String, BacktestResult> backtestResults = {};
  String backtestSummary = '';
  if (data.length >= 60) {
    try {
      backtestResults = BacktestEngine.megaBacktest(data);
      backtestSummary = BacktestEngine.getBacktestSummary(backtestResults);
    } catch (e) {
      debugPrint('[信号引擎] BacktestEngine 失败: $e');
    }
  }

  // 11. 分层策略
  List<TradingStrategy> shortTermStrategies = [];
  List<TradingStrategy> longTermStrategies = [];
  try {
    shortTermStrategies = StrategyBuilder.buildLayeredStrategies(
        data, signals, SignalDuration.shortTerm);
    longTermStrategies = StrategyBuilder.buildLayeredStrategies(
        data, signals, SignalDuration.longTerm);
    // Phase 1: 根据市场结构禁用不兼容策略
    final incompatibleNames =
        getIncompatibleStrategies(marketStructure.structure);
    for (final s in shortTermStrategies) {
      if (incompatibleNames.contains(s.name)) s.isActive = false;
    }
    for (final s in longTermStrategies) {
      if (incompatibleNames.contains(s.name)) s.isActive = false;
    }
  } catch (e) {
    debugPrint('SignalEngine.structureFilter: $e');
  }

  final decisionResult = ShortTermDecisionEngine.evaluate(
    ShortTermDecisionInput(
      data: data,
      quote: quote,
      buySignals: buySignals,
      sellSignals: sellSignals,
      marketContext: marketContext,
      marketStructure: marketStructure,
      nextDayPrediction: nextDayPrediction,
      nextSessionPrediction: nextSessionPrediction,
      tradeLevels: tradeLevels,
      activeStrategies: <TradingStrategy>[
        ...shortTermStrategies,
        ...longTermStrategies,
      ],
      rawComprehensiveScore: compResult.totalScore.toDouble(),
      fundamentalScore: compResult.fundamentalScore,
      newsSentiment: compResult.newsSentiment,
      backtestResults: backtestResults,
    ),
  );
  final shortTermDecision = decisionResult.decision;
  final recommendationDecision = decisionResult.recommendation;
  final totalScore = recommendationDecision.legacyScore;
  final recommendation = recommendationDecision.label;

  // Batch 4: 短线方向预测（复用决策引擎已算好的 5 维分量，无前视）
  final directionForecast = ShortTermDirectionModel.evaluate(
    components: shortTermDecision.directionComponents,
    marketContext: marketContext,
    marketStructure: marketStructure,
    data: data,
    horizonDays: 3,
  );

  // 12. 置信度计算（内部已包含对抗验证 + v2.30: 回测胜率维度 + 新增: 预测准确率反馈）
  final confResult = ConfidenceCalculator.calculate(
    buySignals: buySignals,
    sellSignals: sellSignals,
    signals: signals,
    direction: shortTermDecision.direction,
    last: last,
    quote: quote,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
    marketStructure: marketStructure,
    backtestResults: backtestResults,
    predictionAccuracy: _predictionSupportForRecommendation(
      shortTermDecision.direction,
      nextDayPrediction,
    ),
  );
  // V3 双轨置信度：展示/推荐使用证据一致性，避免把它误当作历史胜率概率；
  // ConfidenceCalculator 的综合诊断结果（含回测胜率、预测支持和对抗验证）单独保留，
  // 供 UI、导出与后续校准诊断使用，两个字段不得再套用旧的 ±15% 后处理公式。
  final confidenceScore = shortTermDecision.evidenceConfidence / 100;
  final calculatorConfidence = confResult.confidenceScore;
  final validatedSignals = confResult.validatedSignals;
  final confidenceBreakdown = ConfidenceCalculator.breakdown(
    buySignals: buySignals,
    sellSignals: sellSignals,
    direction: shortTermDecision.direction,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
    marketStructure: marketStructure,
    backtestResults: backtestResults,
    predictionSupport: _predictionSupportForRecommendation(
      shortTermDecision.direction,
      nextDayPrediction,
    ),
  );

  // 13. 详细推荐理由（增强版：含市场结构/策略/回测/置信度上下文）
  // v3.2: 提前计算维度评分用于评分贡献明细展示
  // v3.42: 维度评分改为5维决策证据，与推荐逻辑100%对齐
  final _dc = shortTermDecision.directionComponents;
  final dimensionScores = <String, double>{
    '趋势': _componentToScore(_dc['trend'] ?? 0),
    '反转动量': _componentToScore(_dc['reversal_momentum'] ?? 0),
    '量价流': _componentToScore(_dc['volume_flow'] ?? 0),
    '相对强度': _componentToScore(_dc['relative_strength'] ?? 0),
    '次交易预测': _componentToScore(_dc['next_session'] ?? 0),
  };
  final reasons = _generateReasons(
    buySignals,
    sellSignals,
    last,
    quote,
    totalScore: totalScore,
    marketStructure: marketStructure,
    backtestResults: backtestResults,
    activeStrategies: [
      ...shortTermStrategies,
      ...longTermStrategies,
    ],
    confidenceScore: confidenceScore,
    recommendation: recommendation,
    dimensionScores: dimensionScores,
    confluenceScoreValue: confluenceResult.score.round(),
  );
  reasons.add(
      '短线交易质量：${shortTermDecision.tradeQualityScore.toStringAsFixed(0)}，风险：${shortTermDecision.riskScore.toStringAsFixed(0)}');

  // 13a. 历史决策反思注入（v2.53: 决策反馈闭环）
  // 异步获取历史反思，不阻塞主分析流程
  List<Map<String, dynamic>> historicalReflections = [];
  if (enableAsyncSideEffects && quote != null) {
    RecommendationTracker()
        .getHistoricalReflections(quote.code)
        .then((reflections) {
      historicalReflections = reflections;
      if (reflections.isNotEmpty) {
        final summary = _generateReflectionSummary(reflections);
        if (summary.isNotEmpty) {
          reasons.add(summary);
        }
      }
    }).catchError((e) {
      debugPrint('[信号引擎] 获取历史反思失败: $e');
    });
  }

  // 13b. AI多智能体辩论（v2.54: 参考 TradingAgents 辩论机制）
  // 异步执行，不阻塞主分析流程
  // 仅当 autoTriggerAI=true 时才触发（用户手动点击"开始分析"）
  if (autoTriggerAI &&
      quote != null &&
      AIConfig.enableAIEnhancement &&
      AILayerProvider.instance.isAvailable) {
    debugPrint('[信号引擎] 启动AI辩论: ${quote.name}(${quote.code}), 评分: $totalScore');
    _runAIDebate(
      quote: quote,
      totalScore: totalScore.toDouble(),
      dimensionScores: {
        '技术面': techResult.totalScore.toDouble(),
        '实时行情': realtimeScore.toDouble(),
        '共振': confluenceResult.score.toDouble(),
        '资金流向': capitalFlowScore ?? 5.0,
        '市场结构': marketStructure.structureScore.toDouble(),
      },
      reasons: reasons,
      newsList: newsList,
      historicalReflections: historicalReflections,
      onAIUpdate: onAIUpdate,
      onAIProgress: onAIProgress,
    ).then((_) {
      debugPrint(
          '[信号引擎] AI辩论完成: ${quote.name}(${quote.code}), reasons数量: ${reasons.length}');
    }).catchError((e) {
      debugPrint('[信号引擎] AI辩论失败: $e');
      if (onAIUpdate != null) {
        onAIUpdate([]);
      }
    });
  } else {
    debugPrint(
        '[信号引擎] AI辩论未启动: quote=$quote, enableAI=${AIConfig.enableAIEnhancement}, available=${AILayerProvider.instance.isAvailable}');
    // AI 不可用：标记终态，避免 UI 永远停留在"AI分析生成中..."
    if (onAIUpdate != null) {
      reasons.add('AI分析暂不可用：未启用AI增强或API Key未配置');
      onAIUpdate([]);
    }
  }

  // 追加打板理由（若当日涨停）
  if (limitUpAnalysis != null) {
    reasons.add(
        '打板分析：${limitUpAnalysis.consecutiveDays}连板${limitUpAnalysis.boardType}，'
        '${limitUpAnalysis.quality}（次日溢价概率${(limitUpAnalysis.premiumProb * 100).round()}%）');
  }

  // 结构转换理由
  if (structureTransition != null) {
    reasons.add(
        '市场结构转换：${structureTransition.description}，'
        '置信度${(structureTransition.confidence * 100).round()}%');
  }

  // v3.34: 追高风险警告——留档数据证明涨幅>3%时胜率仅18%
  if (quote != null && quote.changePct > 3) {
    final warnLevel = quote.changePct > 9.5 ? '极高'
        : quote.changePct > 5 ? '高'
        : '中';
    reasons.add(
        '追高风险(${warnLevel})：当日已涨${quote.changePct.toStringAsFixed(1)}%，'
        '后续回撤概率大');
  }

  // 操作建议（动态仓位：基于ATR波动率、置信度、市场结构）
  final suggestions = SuggestionGenerator.generate(
    recommendation: recommendation,
    data: data,
    last: last,
    quote: quote,
    buySignals: buySignals,
    sellSignals: sellSignals,
    totalScore: totalScore,
    confidenceScore: confidenceScore,
    marketStructure: marketStructure,
  );
  if (recommendationDecision.gates.isNotEmpty) {
    suggestions.insert(0, '短线执行条件未满足，保持观察并等待风险或交易质量改善');
  }

  final detailedReasons = <RecommendationReason>[];
  for (final signal in signals.take(5)) {
    if (signal.confidence != null) {
      detailedReasons.add(RecommendationReason(
        title: signal.signal,
        description: signal.description,
        confidence: signal.confidence!,
        duration: signal.duration == SignalDuration.shortTerm
            ? '短期'
            : signal.duration == SignalDuration.mediumTerm
                ? '中期'
                : '长期',
      ));
    }
  }
  if (marketContext != null) {
    detailedReasons.add(RecommendationReason(
      title: '市场环境',
      description:
          '上证${marketContext.shIndexPct.toStringAsFixed(2)}%，深证${marketContext.szIndexPct.toStringAsFixed(2)}%',
      confidence: 0.7,
      duration: '环境',
    ));
  }

  // v2.30: 推荐追踪 — 覆盖率扩大到个股分析流（原仅在ExploreEngine调用）
  if (enableAsyncSideEffects && totalScore >= 6 && quote != null) {
    final trackResult = AnalysisResult(
      quote: quote,
      signals: signals,
      score: totalScore,
      recommendation: recommendation,
      riskLevel: riskResult.riskLevel,
      confidenceScore: confidenceScore,
      shortTermStrategies: shortTermStrategies,
      longTermStrategies: longTermStrategies,
      marketStructure: marketStructure,
      dimensionScores: dimensionScores,
      shortTermDecision: shortTermDecision,
      recommendationDecision: recommendationDecision,
    );
    // 异步fire-and-forget，不阻塞主分析流程
    RecommendationTracker().track(trackResult).catchError((e) {
      debugPrint('[信号引擎] 推荐跟踪失败: $e');
      return null;
    });
  }

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
    calculatorConfidence: calculatorConfidence,
    marketStructure: marketStructure,
    percentile: percentile,
    limitUpAnalysis: limitUpAnalysis,
    dimensionScores: dimensionScores,
    momentumPersistence: momentumPersistence.toJson(),
    nextDayPrediction:
        _combinedPredictionJson(nextDayPrediction, nextSessionPrediction),
    earlyWarningSignals: earlyWarningSignals,
    shortTermDecision: shortTermDecision,
    recommendationDecision: recommendationDecision,
    directionForecast: directionForecast,
    opportunityScore: opportunityScore,
    intradayProfile: intradayProfile,
    chaseRiskFactor: compResult.chaseRiskFactor,
    marketFactor: compResult.marketFactor,
    sectorMomentumScore: compResult.sectorMomentumScore,
  );
}

/// 生成推荐理由
String _recommendationFromScore(int score, QuoteData? quote) {
  final isST = quote != null && ComprehensiveScorer.isSTStock(quote.name);
  if (isST) {
    if (score >= 5) return '偏多观望';
    if (score >= 3) return '谨慎卖出';
    return '卖出';
  }
  if (score >= 8) return '强烈买入';
  if (score >= 7) return '买入';
  if (score >= 6) return '谨慎买入';
  if (score >= 5) return '偏多观望';
  if (score >= 4) return '偏空观望';
  if (score >= 3) return '谨慎卖出';
  if (score >= 2) return '卖出';
  return '强烈卖出';
}

Map<String, dynamic> _combinedPredictionJson(
  NextDayPredictionResult nextDayPrediction,
  NextSessionPrediction nextSessionPrediction,
) {
  return {
    ...nextDayPrediction.toJson(),
    'next_session': _nextSessionPredictionToJson(nextSessionPrediction),
    'neutral_probability': nextSessionPrediction.neutralProbability,
  };
}

Map<String, dynamic> _nextSessionPredictionToJson(
  NextSessionPrediction prediction,
) {
  return {
    'next_open_up_probability': prediction.nextOpenUpProbability,
    'next_close_up_probability': prediction.nextCloseUpProbability,
    'expected_next_close_return': prediction.expectedNextCloseReturn,
    'downside_risk_probability': prediction.downsideRiskProbability,
    'confidence': prediction.confidence,
    'sample_count': prediction.sampleCount,
    'scenario_tags': prediction.scenarioTags,
    'risk_warnings': prediction.riskWarnings,
    'neutral_probability': prediction.neutralProbability,
  };
}

// Kept temporarily for compatibility with older branch-local tests.
// ignore: unused_element
_NextSessionRecommendationAdjustment _applyNextSessionRiskGate(
  int score,
  String recommendation,
  NextSessionPrediction prediction,
  QuoteData? quote,
) {
  final hasPullbackRisk = prediction.scenarioTags.contains('高位回调风险') ||
      prediction.scenarioTags.contains('长上影分歧') ||
      prediction.scenarioTags.contains('放量滞涨');
  final isAggressiveBuy = recommendation == '强烈买入' || recommendation == '买入';
  if (!hasPullbackRisk) {
    return _NextSessionRecommendationAdjustment(
      score: score,
      recommendation: recommendation,
      reason: '',
    );
  }

  final probability = (prediction.downsideRiskProbability * 100).round();
  final reason =
      '次交易日回调风险：${prediction.scenarioTags.take(2).join('、')}，下跌风险约$probability%，不追高，等待回踩确认';
  if (!isAggressiveBuy) {
    return _NextSessionRecommendationAdjustment(
      score: score,
      recommendation: recommendation,
      reason: reason,
    );
  }

  final cappedScore = score.clamp(0, 6).toInt();
  return _NextSessionRecommendationAdjustment(
    score: cappedScore,
    recommendation: _recommendationFromScore(cappedScore, quote),
    reason: reason,
  );
}

class _NextSessionRecommendationAdjustment {
  final int score;
  final String recommendation;
  final String reason;

  const _NextSessionRecommendationAdjustment({
    required this.score,
    required this.recommendation,
    required this.reason,
  });
}

List<String> _generateReasons(
  List<SignalItem> buySignals,
  List<SignalItem> sellSignals,
  HistoryKline last,
  QuoteData? quote, {
  double? totalScore,
  MarketStructureResult? marketStructure,
  Map<String, BacktestResult>? backtestResults,
  List<TradingStrategy>? activeStrategies,
  double confidenceScore = 0.5,
  String recommendation = '',
  Map<String, double>? dimensionScores,
  int confluenceScoreValue = 0,
}) {
  final reasons = <String>[];
  final buyCount = buySignals.length;
  final sellCount = sellSignals.length;

  final topSignals = [...buySignals, ...sellSignals]
    ..sort((a, b) => b.strength.compareTo(a.strength));
  final summary = RecommendationExplainer.explain(
    dimensionScores: dimensionScores,
    topSignals: topSignals.map((s) => s.signal).take(2).toList(),
    buySignalCount: buyCount,
    sellSignalCount: sellCount,
    confluenceScore: confluenceScoreValue,
    mainNetFlow: quote?.mainNetFlow ?? 0,
    score: totalScore ?? 0,
    recommendation: recommendation,
  );
  if (summary.isNotEmpty) {
    reasons.add('推荐摘要：$summary');
  }

  if (buyCount > sellCount + 1) {
    reasons.add('多个买入信号共振');
  }
  if (sellCount > buyCount + 1) {
    reasons.add('多个卖出信号共振');
  }
  if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma5 > 0) {
    reasons.add('均线多头排列');
  }
  if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma5 > 0) {
    reasons.add('均线空头排列');
  }
  if (last.rsi6 > 70) {
    reasons.add('RSI超买区域');
  }
  if (last.rsi6 < 30 && last.rsi6 > 0) {
    reasons.add('RSI超卖区域');
  }
  if (last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) {
    reasons.add('成交量显著放大');
  }
  if (last.close >= last.open &&
      last.volume < last.volMa5 * 0.7 &&
      last.volMa5 > 0) {
    reasons.add('上涨缩量，动能不足');
  }

  if (quote != null && quote.price > 0) {
    if (quote.changePct > 3) {
      reasons.add('当日涨幅${quote.changePct.toStringAsFixed(1)}%，追高需谨慎');
    }
    if (quote.changePct < -3) {
      reasons.add('当日跌幅${quote.changePct.toStringAsFixed(1)}%，短线偏弱');
    }
    if (quote.mainNetFlow > 0 && quote.mainNetFlowRate > 3) {
      reasons.add('主力资金净流入${quote.mainNetFlowRate.toStringAsFixed(1)}%');
    }
    if (quote.mainNetFlow < 0 && quote.mainNetFlowRate < -3) {
      reasons.add('主力资金净流出${quote.mainNetFlowRate.abs().toStringAsFixed(1)}%');
    }
    if (quote.turnover > 10) {
      reasons.add('换手率${quote.turnover.toStringAsFixed(1)}%，交投过热');
    }
  }

  // --- 增强理由：市场结构上下文 ---
  if (marketStructure != null) {
    final conf = (marketStructure.confidence * 100).toStringAsFixed(0);
    switch (marketStructure.structure) {
      case MarketStructure.bullTrend:
        reasons.add('当前处于牛市结构(置信度$conf%)，顺势做多');
        break;
      case MarketStructure.bearTrend:
        reasons.add('当前处于熊市结构(置信度$conf%)，以防御策略为主，严格控制仓位');
        break;
      case MarketStructure.consolidation:
        reasons.add('当前震荡盘整，适合低买高卖波段操作');
        break;
      case MarketStructure.accumulation:
        reasons.add('当前处于吸筹结构，底部区域逢低布局');
        break;
      case MarketStructure.distribution:
        reasons.add('当前处于派发结构，防范高位回落风险');
    }
  }

  // --- 增强理由：策略指引 ---
  if (activeStrategies != null) {
    final active = activeStrategies.where((s) => s.isActive).toList();
    final incompatible = activeStrategies.where((s) => !s.isActive).toList();
    if (active.isNotEmpty) {
      final strongest =
          active.reduce((a, b) => a.signalStrength > b.signalStrength ? a : b);
      reasons.add(
          '适用${active.length}/${activeStrategies.length}条策略(${incompatible.length}条被市场结构禁用)，最强: ${strongest.name}');
    }
  }

  // --- 增强理由：回测表现 ---
  if (backtestResults != null && backtestResults.isNotEmpty) {
    final totalPf = backtestResults.values
        .fold<double>(0, (sum, r) => sum + r.profitFactor);
    final avgPf = totalPf / backtestResults.length;
    if (avgPf > 1.3) {
      reasons.add('历史回测策略组合盈亏比${avgPf.toStringAsFixed(2)}，策略集合表现较好');
    } else if (avgPf < 1.0) {
      reasons.add('历史回测策略组合盈亏比${avgPf.toStringAsFixed(2)}，过往表现一般，需谨慎');
    }
  }

  // --- 增强理由：置信度提示 ---
  if (totalScore != null && totalScore >= 6) {
    if (confidenceScore > 0.8) {
      reasons.add(
          '多维度确认信号可靠性较高(置信度${(confidenceScore * 100).toStringAsFixed(0)}%)');
    } else if (confidenceScore < 0.5) {
      reasons.add(
          '综合置信度偏低(${(confidenceScore * 100).toStringAsFixed(0)}%)，建议轻仓或观望');
    }
  }

  // --- v3.2: 评分贡献明细 ---
  if (dimensionScores != null && dimensionScores.isNotEmpty) {
    final entries = dimensionScores.entries
        .where((e) => (e.value - 5.0).abs() > 0.01) // 容差过滤中性值
        .toList()
      ..sort((a, b) => (a.value - 5)
          .abs()
          .compareTo((b.value - 5).abs())); // 按偏离度排序（影响大的排前面）
    if (entries.isNotEmpty) {
      final parts = entries.map((e) {
        final diff = e.value - 5;
        final arrow = diff > 0 ? '↑' : '↓';
        return '${e.key}$arrow${diff.abs().toStringAsFixed(1)}';
      }).join(' | ');
      reasons.add('评分贡献: $parts');
    }
  }

  return reasons;
}

/// v2.53: 生成历史决策反思总结
/// 根据已关闭推荐记录的实际收益生成反思摘要，用于增强当前分析的置信度判断
String _generateReflectionSummary(List<Map<String, dynamic>> reflections) {
  if (reflections.isEmpty) return '';

  final totalReturn = reflections.fold<double>(
      0, (sum, r) => sum + (r['day20_return'] as double));
  final avgReturn = totalReturn / reflections.length;
  final positiveCount =
      reflections.where((r) => (r['day20_return'] as double) > 0).length;
  final avgAlpha = reflections.fold<double>(
          0, (sum, r) => sum + (r['alpha_vs_market'] as double)) /
      reflections.length;

  final buf = StringBuffer();
  buf.write('历史表现: 近${reflections.length}次推荐');

  if (avgReturn > 3) {
    buf.write('平均盈利${avgReturn.toStringAsFixed(1)}%');
    if (avgAlpha > 1) buf.write('(跑赢大盘${avgAlpha.toStringAsFixed(1)}%)');
    buf.write(
        '，胜率${((positiveCount / reflections.length) * 100).round()}%，策略有效性较强');
  } else if (avgReturn > 0) {
    buf.write('平均盈利${avgReturn.toStringAsFixed(1)}%');
    if (avgAlpha < -1) buf.write('(跑输大盘${avgAlpha.abs().toStringAsFixed(1)}%)');
    buf.write(
        '，胜率${((positiveCount / reflections.length) * 100).round()}%，表现尚可');
  } else if (avgReturn > -3) {
    buf.write('平均亏损${avgReturn.abs().toStringAsFixed(1)}%');
    buf.write(
        '，胜率${((positiveCount / reflections.length) * 100).round()}%，需谨慎参考');
  } else {
    buf.write('平均亏损${avgReturn.abs().toStringAsFixed(1)}%');
    buf.write(
        '，胜率${((positiveCount / reflections.length) * 100).round()}%，策略近期失效');
  }

  return buf.toString();
}

/// v2.54: AI多智能体辩论 - 异步执行，不阻塞主分析流程
Future<void> _runAIDebate({
  required QuoteData quote,
  required double totalScore,
  required Map<String, dynamic> dimensionScores,
  required List<String> reasons,
  List<dynamic>? newsList,
  required List<Map<String, dynamic>> historicalReflections,
  void Function(List<String> aiReasons)? onAIUpdate,
  void Function(String status, int progress)? onAIProgress,
}) async {
  if (!AILayerProvider.instance.isAvailable) {
    // AI 层不可用：标记终态并通知 UI，避免一直显示"生成中"
    if (onAIUpdate != null) {
      reasons.add('AI分析暂不可用：API Key未配置或AI层未初始化');
      onAIUpdate([]);
    }
    return;
  }

  final newsTitles = <String>[];
  if (newsList != null) {
    for (final news in newsList) {
      if (news is Map<String, dynamic>) {
        final title = (news['title'] ?? news['title_ch'] ?? '').toString();
        if (title.isNotEmpty) newsTitles.add(title);
      }
    }
  }

  final debateEngine = DebateEngine(AILayerProvider.instance);
  final debateResult = await debateEngine.debate(
    stockCode: quote.code,
    stockName: quote.name,
    totalScore: totalScore,
    dimensionScores: dimensionScores,
    newsTitles: newsTitles,
    historicalReflections: historicalReflections,
    onProgress: onAIProgress,
  );

  final aiReasons = <String>[];
  if (debateResult.synthesis.conclusion.isNotEmpty) {
    aiReasons.add('AI分析结论: ${debateResult.synthesis.conclusion}');
  }
  if (debateResult.synthesis.reasons.isNotEmpty) {
    for (final reason in debateResult.synthesis.reasons) {
      aiReasons.add('AI理由: $reason');
    }
  }
  if (debateResult.synthesis.riskFactors.isNotEmpty) {
    for (final risk in debateResult.synthesis.riskFactors) {
      aiReasons.add('AI风险提示: $risk');
    }
  }

  reasons.addAll(aiReasons);
  if (aiReasons.isEmpty) {
    // 辩论失败或返回空结果：标记终态，避免 UI 永远停留在"AI分析生成中..."
    final errMsg = debateResult.error ?? 'API调用失败，请稍后重试';
    reasons.add('AI分析暂不可用：$errMsg');
  }
  if (onAIUpdate != null) {
    onAIUpdate(aiReasons);
  }
}
