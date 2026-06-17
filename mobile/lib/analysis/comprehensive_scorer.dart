import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';

class ComprehensiveScoreResult {
  final int totalScore;
  final String recommendation;
  final FundamentalScore? fundamentalScore;
  final NewsSentiment? newsSentiment;
  final double positionAdvice;
  final String positionLabel;

  ComprehensiveScoreResult({required this.totalScore, required this.recommendation,
    this.fundamentalScore, this.newsSentiment, this.positionAdvice=0.5, this.positionLabel='中性仓位'});
}

class ComprehensiveScorer {
  /// 精确ST检测（避免EAST/WEST等误判）
  static bool isSTStock(String name) => name.startsWith('ST') || name.startsWith('*ST');

  /// 6维度加权：技术28%+资金17%+实时22%+共振15%+情绪10%+基本面8%
  static ComprehensiveScoreResult combine({
    required double technicalScore, required double realtimeScore, required double confluenceScore,
    double? capitalFlowScore, double? marketPositionFactor,
    required QuoteData? quote, required MarketContext? marketContext, required List<dynamic>? newsList,
  }) {
    FundamentalScore? fundamentalScore;
    double fundamentalScoreValue = 5.0;
    if (quote != null && quote.price > 0) {
      fundamentalScore = FundamentalAnalyzer.analyze(quote);
      fundamentalScoreValue = fundamentalScore.totalScore;
    }

    NewsSentiment? newsSentiment;
    double sentimentScoreValue = 5.0;
    if (newsList != null && newsList.isNotEmpty) {
      newsSentiment = NewsSentimentAnalyzer.analyze(newsList);
      sentimentScoreValue = (newsSentiment.score + 10) / 2;
    }

    final capitalScoreValue = capitalFlowScore ?? 5.0;

    double techW=0.28, capW=0.17, realW=0.22, confW=0.15, sentW=0.10, fundW=0.08;
    final hasFund = fundamentalScore != null, hasSent = newsSentiment != null, hasCapital = capitalFlowScore != null;
    if (!hasFund && !hasSent && !hasCapital) { techW=0.45; realW=0.35; confW=0.20; capW=sentW=fundW=0; }
    else if (!hasFund && !hasSent) { techW=0.35; capW=0.20; realW=0.28; confW=0.17; sentW=fundW=0; }
    else if (!hasFund) { techW=0.30; capW=0.18; realW=0.24; confW=0.16; sentW=0.12; fundW=0; }
    else if (!hasSent) { techW=0.30; capW=0.18; realW=0.24; confW=0.16; fundW=0.12; sentW=0; }
    else if (!hasCapital) { techW=0.33; realW=0.25; confW=0.17; sentW=0.12; fundW=0.13; capW=0; }
    else { /* 全维度可用: 使用默认权重 */ }

    final rawScore = (technicalScore*techW + capitalScoreValue*capW + sentimentScoreValue*sentW + realtimeScore*realW + confluenceScore*confW + fundamentalScoreValue*fundW).clamp(0.0, 10.0);

    final positionFactor = marketPositionFactor ?? 1.0;
    double marketAdjustment = 1.0;
    if (marketContext != null) marketAdjustment = marketContext.getMarketAdjustmentFactor();
    final combinedAdjustment = marketAdjustment * 0.4 + positionFactor * 0.6;
    final adjustedScore = (rawScore * combinedAdjustment).clamp(0.0, 10.0);

    // ST股票封顶：最高"偏多观望"，防止推荐高风险标的
    final isST = quote != null && isSTStock(quote.name);
    final int totalScore;
    if (isST) {
      totalScore = (adjustedScore * 0.9 + 1).floor().clamp(1, 5);
    } else {
      totalScore = (adjustedScore * 0.9 + 1).floor().clamp(1, 10);
    }

    String recommendation;
    if (isST) {
      recommendation = totalScore >= 5 ? '偏多观望' : totalScore >= 3 ? '谨慎卖出' : '卖出';
    } else {
      if (totalScore >= 8) recommendation = '强烈买入';
      else if (totalScore >= 7) recommendation = '买入';
      else if (totalScore >= 6) recommendation = '谨慎买入';
      else if (totalScore >= 5) recommendation = '偏多观望';
      else if (totalScore >= 4) recommendation = '偏空观望';
      else if (totalScore >= 3) recommendation = '谨慎卖出';
      else if (totalScore >= 2) recommendation = '卖出';
      else recommendation = '强烈卖出';
    }

    double positionAdvice = adjustedScore / 10.0;
    String positionLabel;
    if (adjustedScore >= 8) positionLabel = '可积极建仓';
    else if (adjustedScore >= 6.5) positionLabel = '可适度参与';
    else if (adjustedScore >= 4.5) positionLabel = '中性仓位';
    else if (adjustedScore >= 3) positionLabel = '减仓观望';
    else positionLabel = '不宜参与';

    return ComprehensiveScoreResult(totalScore: totalScore, recommendation: recommendation,
      fundamentalScore: fundamentalScore, newsSentiment: newsSentiment,
      positionAdvice: positionAdvice, positionLabel: positionLabel);
  }
}
