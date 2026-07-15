import 'package:flutter/foundation.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'signal_validator.dart';
import 'market_structure_analyzer.dart';
import 'backtest_engine.dart';

/// 置信度计算结果
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

/// 置信度计算器：8维置信度 + 对抗验证调整
class ConfidenceCalculator {
  /// 计算综合置信度（0.2-0.95），同时返回对抗验证结果
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
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;
    final isBullishDirection =
        resolvedDirection == RecommendationDirection.bullish;
    final isBearishDirection =
        resolvedDirection == RecommendationDirection.bearish;

    // 1. 信号一致性(35%): 买卖信号比例偏离度，且方向与推荐对齐时加分
    double signalConsistency = 0.5;
    final signalCount = buyCount + sellCount;
    if (signalCount > 0) {
      final dominantDirection = buyCount >= sellCount ? 'buy' : 'sell';
      final dominantCount = buyCount >= sellCount ? buyCount : sellCount;
      final concentration = dominantCount / signalCount;
      final alignment = (isBullishDirection && dominantDirection == 'buy') ||
          (isBearishDirection && dominantDirection == 'sell');
      signalConsistency = alignment
          ? 0.3 + concentration * 0.7
          : 0.3 + (1 - concentration) * 0.4;
    }

    // 2. 基本面支撑(13%): 缩减权重，短线交易PE/PB参考价值有限
    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (isBullishDirection && fundamentalScore.totalScore >= 6) {
        fundamentalSupport =
            (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (isBearishDirection && fundamentalScore.totalScore <= 4) {
        fundamentalSupport =
            (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (isBullishDirection && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3; // 技术面看多但基本面差，降低置信度
      } else if (isBearishDirection && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3; // 技术面看空但基本面好，降低置信度
      } else if (fundamentalScore.totalScore >= 5) {
        fundamentalSupport = 0.5;
      } else if (fundamentalScore.totalScore >= 4) {
        fundamentalSupport = 0.3;
      } else {
        fundamentalSupport = 0.0;
      }
    }

    // 3. 情绪面确认(13%): 新闻情绪与推荐方向一致时加分
    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (isBullishDirection && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (isBearishDirection && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (isBullishDirection && newsSentiment.score < -2) {
        sentimentConfirm = 0.3; // 技术面看多但新闻利空
      } else if (isBearishDirection && newsSentiment.score > 2) {
        sentimentConfirm = 0.3; // 技术面看空但新闻利好
      }
    }

    // 4. 市场环境(13%): 大盘趋势确认
    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (isBullishDirection && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (isBearishDirection && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (isBullishDirection && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (isBearishDirection && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    // 5. 市场结构确认(13%): 分裂自原marketConfirm，结构趋势与信号方向一致时加分
    double structureConfirm = 0.5;
    if (marketStructure != null) {
      final isBullish =
          marketStructure.structure == MarketStructure.bullTrend ||
              marketStructure.structure == MarketStructure.accumulation;
      final isBearish =
          marketStructure.structure == MarketStructure.bearTrend ||
              marketStructure.structure == MarketStructure.distribution;
      final structureConfidence = marketStructure.confidence.clamp(0.3, 1.0);
      if (isBullishDirection && isBullish) {
        structureConfirm = 0.3 + structureConfidence * 0.7;
      } else if (isBearishDirection && isBearish) {
        structureConfirm = 0.3 + structureConfidence * 0.7;
      } else if (isBullishDirection && isBearish) {
        structureConfirm = 1.0 - (0.3 + structureConfidence * 0.7);
      } else if (isBearishDirection && isBullish) {
        structureConfirm = 1.0 - (0.3 + structureConfidence * 0.7);
      } else {
        structureConfirm = 0.5;
      }
    }

    // 6. 信号时效性(12%): 短中期信号权重高于长期（短线交易核心维度）
    // P0-6修复：按推荐方向过滤，买入推荐只计近期买入信号，卖出推荐只计近期卖出信号
    double signalFreshness = 0.5;
    final directionalSignals = switch (resolvedDirection) {
      RecommendationDirection.bullish => buySignals,
      RecommendationDirection.bearish => sellSignals,
      RecommendationDirection.neutral => const <SignalItem>[],
    };
    final directionalRecentSignals = directionalSignals
        .where((s) =>
            s.duration == SignalDuration.shortTerm ||
            s.duration == SignalDuration.mediumTerm)
        .length;
    if (signalCount > 0 && directionalRecentSignals > 0) {
      signalFreshness = 0.3 + directionalRecentSignals / signalCount * 0.7;
    }

    // 7. 回测胜率(8%): 历史回测平均胜率映射到0-1置信度
    double backtestWinRate = 0.5;
    if (backtestResults != null && backtestResults.isNotEmpty) {
      final winRates = backtestResults.values
          .where((r) => r.totalSignals > 0 && r.winRate > 0)
          .map((r) => r.winRate)
          .toList();
      if (winRates.isNotEmpty) {
        final avgWinRate = winRates.reduce((a, b) => a + b) / winRates.length;
        backtestWinRate = (0.3 + avgWinRate * 0.7).clamp(0.0, 1.0);
      }
    }

    // 8. 预测方向支持(8%): 当前相似模式与推荐方向的一致程度
    double predictionAccuracyVal = predictionAccuracy ?? 0.5;

    // 8维权重归一化至1.0：原有7维各按比例缩减8%，新维度预测准确率占8%
    // 权重分配: 信号一致性29% + 基本面支撑11% + 情绪确认11% + 市场环境11% + 结构确认11% + 信号时效性11% + 回测胜率8% + 预测准确率8%
    var confidenceScore = (signalConsistency * 29 +
            fundamentalSupport * 11 +
            sentimentConfirm * 11 +
            marketConfirm * 11 +
            structureConfirm * 11 +
            signalFreshness * 11 +
            backtestWinRate * 8 +
            predictionAccuracyVal * 8) /
        100.0;
    confidenceScore = confidenceScore.clamp(0.3, 0.95);

    // 信号对抗验证调整
    List<ValidatedSignal> validatedSignals = [];
    try {
      validatedSignals = SignalValidator.validate(signals, quote, last);
    } catch (e) {
      debugPrint('[置信度] 信号验证失败，降级使用原始信号: $e');
    }

    // 对抗验证结果反馈到置信度：根据反对点数量和强度调整
    double validationAdjustment = 0.0;
    if (validatedSignals.isNotEmpty) {
      for (final vs in validatedSignals) {
        // 如果信号被对抗验证大幅削弱，降低置信度
        if (vs.adjustedConfidence < 0.4) {
          validationAdjustment -= 0.05;
        } else if (vs.adjustedConfidence < 0.5) {
          validationAdjustment -= 0.02;
        }
      }
      // 将对抗验证调整应用到置信度
      confidenceScore =
          (confidenceScore + validationAdjustment).clamp(0.2, 0.95);
    }

    return ConfidenceCalcResult(
      confidenceScore: confidenceScore,
      validatedSignals: validatedSignals,
      predictionAccuracy: predictionAccuracyVal,
    );
  }

  /// 返回置信度各维度分项得分
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
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;
    final signalCount = buyCount + sellCount;
    final isBullishDirection =
        resolvedDirection == RecommendationDirection.bullish;
    final isBearishDirection =
        resolvedDirection == RecommendationDirection.bearish;

    // 1. 信号一致性(29%): 与calculate方法权重一致
    double signalConsistency = 0.5;
    if (signalCount > 0) {
      final dominantDirection = buyCount >= sellCount ? 'buy' : 'sell';
      final dominantCount = buyCount >= sellCount ? buyCount : sellCount;
      final concentration = dominantCount / signalCount;
      final alignment = (isBullishDirection && dominantDirection == 'buy') ||
          (isBearishDirection && dominantDirection == 'sell');
      signalConsistency = alignment
          ? 0.3 + concentration * 0.7
          : 0.3 + (1 - concentration) * 0.4;
    }

    // 2. 基本面支撑(11%): 缩减权重，短线交易PE/PB参考价值有限
    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (isBullishDirection && fundamentalScore.totalScore >= 6) {
        fundamentalSupport =
            (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (isBearishDirection && fundamentalScore.totalScore <= 4) {
        fundamentalSupport =
            (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (isBullishDirection && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3;
      } else if (isBearishDirection && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3;
      } else if (fundamentalScore.totalScore >= 5) {
        fundamentalSupport = 0.5;
      } else if (fundamentalScore.totalScore >= 4) {
        fundamentalSupport = 0.3;
      } else {
        fundamentalSupport = 0.0;
      }
    }

    // 3. 情绪面确认(11%)
    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (isBullishDirection && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (isBearishDirection && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (isBullishDirection && newsSentiment.score < -2) {
        sentimentConfirm = 0.3;
      } else if (isBearishDirection && newsSentiment.score > 2) {
        sentimentConfirm = 0.3;
      }
    }

    // 4. 市场环境(11%): 大盘趋势权重，短线需顺势操作
    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (isBullishDirection && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (isBearishDirection && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (isBullishDirection && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (isBearishDirection && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    // 5. 结构确认(11%)
    double structureConfirm = 0.5;
    if (marketStructure != null) {
      final isBullish =
          marketStructure.structure == MarketStructure.bullTrend ||
              marketStructure.structure == MarketStructure.accumulation;
      final isBearish =
          marketStructure.structure == MarketStructure.bearTrend ||
              marketStructure.structure == MarketStructure.distribution;
      final structureConfidence = marketStructure.confidence.clamp(0.3, 1.0);
      if (isBullishDirection && isBullish) {
        structureConfirm = 0.3 + structureConfidence * 0.7;
      } else if (isBearishDirection && isBearish) {
        structureConfirm = 0.3 + structureConfidence * 0.7;
      } else if (isBullishDirection && isBearish) {
        structureConfirm = 1.0 - (0.3 + structureConfidence * 0.7);
      } else if (isBearishDirection && isBullish) {
        structureConfirm = 1.0 - (0.3 + structureConfidence * 0.7);
      } else {
        structureConfirm = 0.5;
      }
    }

    // 6. 信号时效性(11%) — P0-6修复：按方向过滤
    double signalFreshness = 0.5;
    final directionalSignals = switch (resolvedDirection) {
      RecommendationDirection.bullish => buySignals,
      RecommendationDirection.bearish => sellSignals,
      RecommendationDirection.neutral => const <SignalItem>[],
    };
    final directionalRecent = directionalSignals
        .where((s) =>
            s.duration == SignalDuration.shortTerm ||
            s.duration == SignalDuration.mediumTerm)
        .length;
    if (signalCount > 0 && directionalRecent > 0) {
      signalFreshness = 0.3 + directionalRecent / signalCount * 0.7;
    }

    // 7. 回测胜率(8%): 历史回测平均胜率映射到0-1置信度
    double backtestWinRate = 0.5;
    if (backtestResults != null && backtestResults.isNotEmpty) {
      final winRates = backtestResults.values
          .where((r) => r.totalSignals > 0 && r.winRate > 0)
          .map((r) => r.winRate)
          .toList();
      if (winRates.isNotEmpty) {
        final avgWinRate = winRates.reduce((a, b) => a + b) / winRates.length;
        backtestWinRate = (0.3 + avgWinRate * 0.7).clamp(0.0, 1.0);
      }
    }

    final predictionSupportValue = predictionSupport ?? 0.5;

    return {
      'signal_consistency': signalConsistency,
      'fundamental_support': fundamentalSupport,
      'sentiment_confirm': sentimentConfirm,
      'market_confirm': marketConfirm,
      'structure_confirm': structureConfirm,
      'signal_freshness': signalFreshness,
      'historical_winrate': backtestWinRate,
      'prediction_support': predictionSupportValue,
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
