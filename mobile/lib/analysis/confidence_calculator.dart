import '../models/stock_models.dart';
import 'signal_validator.dart';

/// 置信度计算结果
class ConfidenceCalcResult {
  final double confidenceScore;
  final List<ValidatedSignal> validatedSignals;

  ConfidenceCalcResult({required this.confidenceScore, required this.validatedSignals});
}

/// 置信度计算器：5维置信度 + 对抗验证调整
class ConfidenceCalculator {
  /// 计算综合置信度（0.2-0.95），同时返回对抗验证结果
  static ConfidenceCalcResult calculate({
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required List<SignalItem> signals,
    required int totalScore,
    required HistoryKline last,
    required QuoteData? quote,
    FundamentalScore? fundamentalScore,
    NewsSentiment? newsSentiment,
    MarketContext? marketContext,
  }) {
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;

    // 1. 信号一致性(30%): 买卖信号比例偏离度，且方向与推荐对齐时加分
    double signalConsistency = 0.5;
    final signalCount = buyCount + sellCount;
    if (signalCount > 0) {
      final dominantDirection = buyCount >= sellCount ? 'buy' : 'sell';
      final dominantCount = buyCount > sellCount ? buyCount : sellCount;
      final concentration = dominantCount / signalCount;
      final alignment = (totalScore >= 7 && dominantDirection == 'buy') ||
                        (totalScore <= 4 && dominantDirection == 'sell') ||
                        (totalScore == 6 && dominantDirection == 'buy') ||
                        (totalScore == 5 && dominantDirection == 'sell');
      signalConsistency = alignment
          ? 0.3 + concentration * 0.7
          : 0.3 + (1 - concentration) * 0.4;
    }

    // 2. 基本面支撑(25%): 基本面评分与推荐方向一致时加分
    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (totalScore >= 7 && fundamentalScore.totalScore >= 6) {
        fundamentalSupport = (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore <= 4 && fundamentalScore.totalScore <= 4) {
        fundamentalSupport = (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore >= 7 && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3; // 技术面看多但基本面差，降低置信度
      } else if (totalScore <= 4 && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3; // 技术面看空但基本面好，降低置信度
      }
    }

    // 3. 情绪面确认(20%): 新闻情绪与推荐方向一致时加分
    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (totalScore >= 7 && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (totalScore <= 4 && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (totalScore >= 7 && newsSentiment.score < -2) {
        sentimentConfirm = 0.3; // 技术面看多但新闻利空
      } else if (totalScore <= 4 && newsSentiment.score > 2) {
        sentimentConfirm = 0.3; // 技术面看空但新闻利好
      }
    }

    // 4. 市场环境(15%): 大盘趋势与推荐方向一致时加分
    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (totalScore >= 7 && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (totalScore <= 4 && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (totalScore >= 7 && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (totalScore <= 4 && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    // 5. 信号新鲜度(10%): 近期信号权重高于远期
    double signalFreshness = 0.5;
    final recentBuySignals = buySignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    final recentSellSignals = sellSignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    if (recentBuySignals + recentSellSignals > 0) {
      signalFreshness = 0.3 + (recentBuySignals + recentSellSignals) / (signalCount > 0 ? signalCount : 1) * 0.7;
    }

    var confidenceScore = (signalConsistency * 0.30 +
        fundamentalSupport * 0.25 +
        sentimentConfirm * 0.20 +
        marketConfirm * 0.15 +
        signalFreshness * 0.10).clamp(0.3, 0.95);

    // 信号对抗验证调整
    List<ValidatedSignal> validatedSignals = [];
    try {
      validatedSignals = SignalValidator.validate(signals, quote, last);
    } catch (_) {
      // 对抗验证失败不影响主流程
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
      confidenceScore = (confidenceScore + validationAdjustment).clamp(0.2, 0.95);
    }

    return ConfidenceCalcResult(confidenceScore: confidenceScore, validatedSignals: validatedSignals);
  }

  /// 返回置信度各维度分项得分
  static Map<String, double> breakdown({
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required int totalScore,
    FundamentalScore? fundamentalScore,
    NewsSentiment? newsSentiment,
    MarketContext? marketContext,
  }) {
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;
    final signalCount = buyCount + sellCount;

    // 1. 信号一致性(30%): 与calculate方法保持一致
    double signalConsistency = 0.5;
    if (signalCount > 0) {
      final dominantDirection = buyCount >= sellCount ? 'buy' : 'sell';
      final dominantCount = buyCount > sellCount ? buyCount : sellCount;
      final concentration = dominantCount / signalCount;
      final alignment = (totalScore >= 7 && dominantDirection == 'buy') ||
                        (totalScore <= 4 && dominantDirection == 'sell') ||
                        (totalScore == 6 && dominantDirection == 'buy') ||
                        (totalScore == 5 && dominantDirection == 'sell');
      signalConsistency = alignment
          ? 0.3 + concentration * 0.7
          : 0.3 + (1 - concentration) * 0.4;
    }

    // 2. 基本面支撑(25%)
    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (totalScore >= 7 && fundamentalScore.totalScore >= 6) {
        fundamentalSupport = (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore <= 4 && fundamentalScore.totalScore <= 4) {
        fundamentalSupport = (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore >= 7 && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3;
      } else if (totalScore <= 4 && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3;
      }
    }

    // 3. 情绪面确认(20%)
    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (totalScore >= 7 && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (totalScore <= 4 && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (totalScore >= 7 && newsSentiment.score < -2) {
        sentimentConfirm = 0.3;
      } else if (totalScore <= 4 && newsSentiment.score > 2) {
        sentimentConfirm = 0.3;
      }
    }

    // 4. 市场环境(15%)
    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (totalScore >= 7 && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (totalScore <= 4 && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (totalScore >= 7 && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (totalScore <= 4 && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    // 5. 信号新鲜度(10%)
    double signalFreshness = 0.5;
    final recentBuySignals = buySignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    final recentSellSignals = sellSignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    if (recentBuySignals + recentSellSignals > 0) {
      signalFreshness = 0.3 + (recentBuySignals + recentSellSignals) / (signalCount > 0 ? signalCount : 1) * 0.7;
    }

    return {
      'signal_consistency': signalConsistency,
      'fundamental_support': fundamentalSupport,
      'sentiment_confirm': sentimentConfirm,
      'market_confirm': marketConfirm,
      'signal_freshness': signalFreshness,
    };
  }
}
