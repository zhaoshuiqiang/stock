import 'package:flutter/foundation.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'evidence_confidence_calculator.dart';
import 'market_structure_analyzer.dart';
import 'signal_validator.dart';
import 'backtest_engine.dart';

class ConfidenceCalcResult {
  final double confidenceScore;
  final List<ValidatedSignal> validatedSignals;
  final double predictionAccuracy;

  ConfidenceCalcResult({
    required this.confidenceScore,
    required this.validatedSignals,
    this.predictionAccuracy = 0.5,
  });
}

class ConfidenceCalculator {
  static ConfidenceCalcResult calculate({
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required List<SignalItem> signals,
    RecommendationDirection? direction,
    int? totalScore,
    required HistoryKline last,
    required QuoteData? quote,
    FundamentalScore? fundamentalScore,
    NewsSentiment? newsSentiment,
    MarketContext? marketContext,
    MarketStructureResult? marketStructure,
    Map<String, BacktestResult>? backtestResults,
    double? predictionAccuracy,
  }) {
    final resolvedDirection = direction ?? _legacyDirection(totalScore);
    final directionalSignals = switch (resolvedDirection) {
      RecommendationDirection.bullish => buySignals,
      RecommendationDirection.bearish => sellSignals,
      RecommendationDirection.neutral => const <SignalItem>[],
    };

    final evidenceResult = EvidenceConfidenceCalculator.calculate(
      directionComponents: _buildDirectionComponents(buySignals, sellSignals, last, quote, marketContext),
      directionalSignals: directionalSignals,
      dataQualityFlags: const [],
      fundamentalScore: fundamentalScore,
      newsSentiment: newsSentiment,
      marketContext: marketContext,
      marketStructure: marketStructure,
      backtestResults: backtestResults,
      direction: resolvedDirection,
    );

    var confidenceScore = evidenceResult.score / 100.0;
    confidenceScore = confidenceScore.clamp(0.3, 0.95);

    List<ValidatedSignal> validatedSignals = [];
    try {
      validatedSignals = SignalValidator.validate(signals, quote, last);
    } catch (e) {
      debugPrint('[置信度] 信号验证失败，降级使用原始信号: $e');
    }

    double validationAdjustment = 0.0;
    if (validatedSignals.isNotEmpty) {
      for (final vs in validatedSignals) {
        if (vs.adjustedConfidence < 0.4) {
          validationAdjustment -= 0.05;
        } else if (vs.adjustedConfidence < 0.5) {
          validationAdjustment -= 0.02;
        }
      }
      confidenceScore =
          (confidenceScore + validationAdjustment).clamp(0.2, 0.95);
    }

    return ConfidenceCalcResult(
      confidenceScore: confidenceScore,
      validatedSignals: validatedSignals,
      predictionAccuracy: predictionAccuracy ?? 0.5,
    );
  }

  static Map<String, double> breakdown({
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    RecommendationDirection? direction,
    int? totalScore,
    FundamentalScore? fundamentalScore,
    NewsSentiment? newsSentiment,
    MarketContext? marketContext,
    MarketStructureResult? marketStructure,
    Map<String, BacktestResult>? backtestResults,
    double? predictionSupport,
  }) {
    final resolvedDirection = direction ?? _legacyDirection(totalScore);
    final result = EvidenceConfidenceCalculator.calculate(
      directionComponents: _buildDirectionComponents(
        buySignals, sellSignals, null, null, marketContext,
      ),
      directionalSignals: switch (resolvedDirection) {
        RecommendationDirection.bullish => buySignals,
        RecommendationDirection.bearish => sellSignals,
        RecommendationDirection.neutral => const <SignalItem>[],
      },
      dataQualityFlags: const [],
      fundamentalScore: fundamentalScore,
      newsSentiment: newsSentiment,
      marketContext: marketContext,
      marketStructure: marketStructure,
      backtestResults: backtestResults,
      direction: resolvedDirection,
    );

    return {
      'signal_consistency': result.componentAgreement / 100,
      'fundamental_support': result.fundamentalSupport / 100,
      'sentiment_confirm': result.sentimentConfirm / 100,
      'market_confirm': result.marketEnvironment / 100,
      'structure_confirm': result.marketEnvironment / 100,
      'signal_freshness': result.freshness / 100,
      'historical_winrate': result.backtestWinRate / 100,
      'prediction_support': (predictionSupport ?? 0.5),
    };
  }

  static Map<String, double> _buildDirectionComponents(
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
    HistoryKline? last,
    QuoteData? quote,
    MarketContext? marketContext,
  ) {
    double trend = 0, reversal = 0, volumeFlow = 0, relStrength = 0, nextSession = 0;

    if (last != null && last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20) trend = 0.45;
      else if (last.ma5 < last.ma10 && last.ma10 < last.ma20) trend = -0.45;
    }

    for (final s in buySignals) {
      final v = s.strength / 100 * (s.confidence ?? 0.8);
      if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.indicator == 'WR') reversal += v * 0.3;
      else if (s.indicator == 'VOL' || s.indicator == 'OBV') volumeFlow += v * 0.3;
      else trend += v * 0.2;
    }
    for (final s in sellSignals) {
      final v = s.strength / 100 * (s.confidence ?? 0.8);
      if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.indicator == 'WR') reversal -= v * 0.3;
      else if (s.indicator == 'VOL' || s.indicator == 'OBV') volumeFlow -= v * 0.3;
      else trend -= v * 0.2;
    }

    if (quote != null && marketContext != null) {
      relStrength = ((quote.changePct - marketContext.avgChangePct) / 5).clamp(-1.0, 1.0);
    }

    return {
      'trend': trend.clamp(-1.0, 1.0),
      'reversal_momentum': reversal.clamp(-1.0, 1.0),
      'volume_flow': volumeFlow.clamp(-1.0, 1.0),
      'relative_strength': relStrength.clamp(-1.0, 1.0),
      'next_session': nextSession.clamp(-1.0, 1.0),
    };
  }

  static RecommendationDirection _legacyDirection(int? totalScore) {
    if (totalScore != null && totalScore >= 6) {
      return RecommendationDirection.bullish;
    }
    if (totalScore != null && totalScore <= 4) {
      return RecommendationDirection.bearish;
    }
    return RecommendationDirection.neutral;
  }
}
