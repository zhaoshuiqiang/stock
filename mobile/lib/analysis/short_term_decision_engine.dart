import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'backtest_engine.dart';
import 'directional_evidence_builder.dart';
import 'evidence_confidence_calculator.dart';
import 'market_structure_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import 'primary_strategy_selector.dart';
import 'recommendation_policy.dart';
import 'scoring_config.dart';
import 'short_term_risk_evaluator.dart';
import 'strategy_engine.dart';
import 'sector_momentum_calculator.dart';
import 'trade_quality_evaluator.dart';

class ShortTermDecisionInput {
  final List<HistoryKline> data;
  final QuoteData? quote;
  final List<SignalItem> buySignals;
  final List<SignalItem> sellSignals;
  final MarketContext? marketContext;
  final MarketStructureResult? marketStructure;
  @Deprecated('V3 derives relative strength from completed stock/market data')
  final double? industryRelativeStrength;
  final NextDayPredictionResult nextDayPrediction;
  final NextSessionPrediction nextSessionPrediction;
  final Map<String, dynamic>? tradeLevels;
  final List<TradingStrategy> activeStrategies;
  final double rawComprehensiveScore;
  final FundamentalScore? fundamentalScore;
  final NewsSentiment? newsSentiment;
  final Map<String, BacktestResult>? backtestResults;
  final SectorMomentumResult? sectorMomentum;

  const ShortTermDecisionInput({
    required this.data,
    this.quote,
    required this.buySignals,
    required this.sellSignals,
    this.marketContext,
    this.marketStructure,
    this.industryRelativeStrength,
    required this.nextDayPrediction,
    required this.nextSessionPrediction,
    this.tradeLevels,
    required this.activeStrategies,
    required this.rawComprehensiveScore,
    this.fundamentalScore,
    this.newsSentiment,
    this.backtestResults,
    this.sectorMomentum,
  });
}

class ShortTermDecisionResult {
  final ShortTermDecision decision;
  final RecommendationDecision recommendation;

  const ShortTermDecisionResult({
    required this.decision,
    required this.recommendation,
  });
}

class ShortTermDecisionEngine {
  /// v4.5: 循证校准开启时给模型版本追加标签，使新旧口径的决策统计不混合；
  /// 关闭时保持 'short-term-v3' 字节不变。
  static String get modelVersion => ScoringConfig.useRecalibratedDirection
      ? 'short-term-v3+dir-recal-v1'
      : 'short-term-v3';

  static ShortTermDecisionResult evaluate(ShortTermDecisionInput input) {
    final evidence = DirectionalEvidenceBuilder.build(
      DirectionalEvidenceInput(
        data: input.data,
        buySignals: input.buySignals,
        sellSignals: input.sellSignals,
        quote: input.quote,
        marketContext: input.marketContext,
        marketStructure: input.marketStructure,
        stockLastCompletedChangePct:
            input.data.isEmpty ? null : input.data.last.changePct,
        nextDayPrediction: input.nextDayPrediction,
        nextSessionPrediction: input.nextSessionPrediction,
        sectorMomentum: input.sectorMomentum,
      ),
    );
    final direction = _directionOf(evidence.directionScore);
    final directionalSignals = switch (direction) {
      RecommendationDirection.bullish => input.buySignals,
      RecommendationDirection.bearish => input.sellSignals,
      RecommendationDirection.neutral => const <SignalItem>[],
    };
    final confidence = EvidenceConfidenceCalculator.calculate(
      directionComponents: evidence.components,
      directionalSignals: directionalSignals,
      dataQualityFlags: evidence.dataQualityFlags,
      fundamentalScore: input.fundamentalScore,
      newsSentiment: input.newsSentiment,
      marketContext: input.marketContext,
      marketStructure: input.marketStructure,
      backtestResults: input.backtestResults,
      direction: direction,
    );
    final selection = PrimaryStrategySelector.select(
      strategies: input.activeStrategies,
      direction: direction,
      evidenceConfidence: confidence.score,
    );
    final quality = TradeQualityEvaluator.evaluate(
      data: input.data,
      directionalSignals: directionalSignals,
      direction: direction,
      quote: input.quote,
      tradeLevels: input.tradeLevels,
      primaryStrategySupported: selection.primary != null,
    );
    final risk = ShortTermRiskEvaluator.evaluate(
      data: input.data,
      quote: input.quote,
      dataQualityFlags: evidence.dataQualityFlags,
    );
    final decision = ShortTermDecision(
      directionScore: evidence.directionScore,
      tradeQualityScore: quality.score,
      riskScore: risk.score,
      evidenceConfidence: confidence.score,
      direction: direction,
      marketRegime: evidence.marketRegime,
      directionComponents: evidence.components,
      qualityComponents: quality.components,
      riskComponents: risk.components,
      primaryStrategyId: selection.primary?.id,
      primaryStrategyName: selection.primary?.name,
      supportingStrategyIds: selection.supportingIds,
      dataQualityFlags: evidence.dataQualityFlags,
      evidenceTradeDate: input.data.isEmpty ? null : input.data.last.date,
      modelVersion: modelVersion,
      rawComprehensiveScore: input.rawComprehensiveScore,
      sectorMomentum: input.sectorMomentum,
    );
    return ShortTermDecisionResult(
      decision: decision,
      recommendation: RecommendationPolicy.evaluate(decision),
    );
  }

  static RecommendationDirection _directionOf(double score) {
    if (score >= kDirectionBullishThreshold)
      return RecommendationDirection.bullish;
    if (score <= kDirectionBearishThreshold)
      return RecommendationDirection.bearish;
    return RecommendationDirection.neutral;
  }
}
