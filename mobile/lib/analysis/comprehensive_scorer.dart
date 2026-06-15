import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';

class ComprehensiveScoreResult {
  final int totalScore;
  final String recommendation;
  final FundamentalScore? fundamentalScore;
  final NewsSentiment? newsSentiment;

  ComprehensiveScoreResult({
    required this.totalScore,
    required this.recommendation,
    this.fundamentalScore,
    this.newsSentiment,
  });
}

class ComprehensiveScorer {
  static ComprehensiveScoreResult combine({
    required double technicalScore,
    required double realtimeScore,
    required double confluenceScore,
    required QuoteData? quote,
    required MarketContext? marketContext,
    required List<dynamic>? newsList,
  }) {
    // 基本面评分
    FundamentalScore? fundamentalScore;
    double fundamentalScoreValue = 5.0; // 默认中性
    if (quote != null && quote.price > 0) {
      fundamentalScore = FundamentalAnalyzer.analyze(quote);
      fundamentalScoreValue = fundamentalScore.totalScore;
    }

    // 新闻情绪评分 (-10 ~ +10, 映射到 0-10)
    NewsSentiment? newsSentiment;
    double sentimentScoreValue = 5.0; // 默认中性
    if (newsList != null && newsList.isNotEmpty) {
      newsSentiment = NewsSentimentAnalyzer.analyze(newsList);
      // 映射 [-10, +10] → [0, 10]
      sentimentScoreValue = (newsSentiment.score + 10) / 2;
    }

    // 动态权重分配：基本面/情绪数据缺失时权重重分配给技术面和实时行情
    // 权重之和必须为1.0，否则评分系统性偏低
    // 短线模式权重：技术面和实时行情为主，基本面为辅
    double techW = 0.38, fundW = 0.10, sentW = 0.12, realW = 0.22, confW = 0.18;
    final hasFund = fundamentalScore != null;
    final hasSent = newsSentiment != null;
    if (!hasFund && !hasSent) {
      techW = 0.45; realW = 0.30; confW = 0.25; fundW = 0; sentW = 0;
    } else if (!hasFund) {
      techW = 0.42; realW = 0.25; confW = 0.20; sentW = 0.13; fundW = 0;
    } else if (!hasSent) {
      techW = 0.42; realW = 0.25; confW = 0.20; fundW = 0.13; sentW = 0;
    }

    final rawScore = (technicalScore * techW +
        fundamentalScoreValue * fundW +
        sentimentScoreValue * sentW +
        realtimeScore * realW +
        confluenceScore * confW).clamp(0.0, 10.0);

    // 市场环境调节
    double marketAdjustment = 1.0;
    if (marketContext != null) {
      marketAdjustment = marketContext.getMarketAdjustmentFactor();
    }
    final adjustedScore = (rawScore * marketAdjustment).clamp(0.0, 10.0);

    // 映射到10级整分（1-10）
    final totalScore = (adjustedScore / 10.0 * 9 + 1).round().clamp(1, 10);

    // 10级推荐（8档）
    String recommendation;
    if (totalScore >= 9) {
      recommendation = '强烈买入';
    } else if (totalScore >= 8) {
      recommendation = '买入';
    } else if (totalScore >= 7) {
      recommendation = '谨慎买入';
    } else if (totalScore >= 6) {
      recommendation = '偏多观望';
    } else if (totalScore >= 5) {
      recommendation = '偏空观望';
    } else if (totalScore >= 4) {
      recommendation = '谨慎卖出';
    } else if (totalScore >= 3) {
      recommendation = '卖出';
    } else {
      recommendation = '强烈卖出';
    }

    return ComprehensiveScoreResult(
      totalScore: totalScore,
      recommendation: recommendation,
      fundamentalScore: fundamentalScore,
      newsSentiment: newsSentiment,
    );
  }
}
