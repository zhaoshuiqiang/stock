import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'directional_evidence_builder.dart';
import 'evidence_confidence_calculator.dart';
import 'market_structure_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import 'primary_strategy_selector.dart';
import 'recommendation_policy.dart';
import 'short_term_risk_evaluator.dart';
import 'strategy_engine.dart';
import 'trade_quality_evaluator.dart';

class ShortTermDecisionInput {
  final List<HistoryKline> data;
  final QuoteData? quote;
  final List<SignalItem> buySignals;
  final List<SignalItem> sellSignals;
  final MarketContext? marketContext;
  final MarketStructureResult? marketStructure;
  final double? industryRelativeStrength;
  final NextDayPredictionResult nextDayPrediction;
  final NextSessionPrediction nextSessionPrediction;
  final Map<String, dynamic>? tradeLevels;
  final List<TradingStrategy> activeStrategies;
  final double rawComprehensiveScore;

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
  static const String modelVersion = 'short-term-v2';

  static ShortTermDecisionResult evaluate(ShortTermDecisionInput input) {
    final evidence = DirectionalEvidenceBuilder.build(
      DirectionalEvidenceInput(
        data: input.data,
        buySignals: input.buySignals,
        sellSignals: input.sellSignals,
        quote: input.quote,
        marketContext: input.marketContext,
        marketStructure: input.marketStructure,
        industryRelativeStrength: input.industryRelativeStrength,
        nextDayPrediction: input.nextDayPrediction,
        nextSessionPrediction: input.nextSessionPrediction,
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
    );
    final selection = PrimaryStrategySelector.select(
      strategies: input.activeStrategies,
      direction: direction,
      evidenceConfidence: confidence.score,
    );
    final quality = TradeQualityEvaluator.evaluate(
      data: input.data,
      directionalSignals: directionalSignals,
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
      modelVersion: modelVersion,
      rawComprehensiveScore: input.rawComprehensiveScore,
    );
    return ShortTermDecisionResult(
      decision: decision,
      recommendation: RecommendationPolicy.evaluate(decision),
    );
  }

  static RecommendationDirection _directionOf(double score) {
    if (score >= 12) return RecommendationDirection.bullish;
    if (score <= -12) return RecommendationDirection.bearish;
    return RecommendationDirection.neutral;
  }
}
