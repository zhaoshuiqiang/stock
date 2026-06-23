import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';
import 'market_structure_analyzer.dart';

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

  /// 7维度加权：技术22%+资金13%+实时12%+共振12%+情绪8%+基本面23%+结构10%
  static ComprehensiveScoreResult combine({
    required double technicalScore, required double realtimeScore, required double confluenceScore,
    double? capitalFlowScore, double? marketPositionFactor,
    required QuoteData? quote, required MarketContext? marketContext, required List<dynamic>? newsList,
    MarketStructureResult? marketStructure,
    double? currentChangePct,
    double? bias6Abs,
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
    final structureScoreValue = marketStructure?.structureScore ?? 5.0;

    // 7维权重: Tech/Cap/Real/Conf/Sent/Fund/Struct
    // 结构分析始终可用(基于K线)，不需要自适应回退
    double techW=0.22, capW=0.13, realW=0.12, confW=0.12, sentW=0.08, fundW=0.23, structW=0.10;
    final hasFund = fundamentalScore != null, hasSent = newsSentiment != null, hasCapital = capitalFlowScore != null;
    if (!hasFund && !hasSent && !hasCapital) { techW=0.39; realW=0.21; confW=0.22; structW=0.18; capW=sentW=fundW=0; }
    else if (!hasFund && !hasSent) { techW=0.32; capW=0.19; realW=0.17; confW=0.17; structW=0.15; sentW=fundW=0; }
    else if (!hasFund) { techW=0.29; capW=0.17; realW=0.16; confW=0.15; sentW=0.10; structW=0.13; fundW=0; }
    else if (!hasSent) { techW=0.24; capW=0.14; realW=0.13; confW=0.13; fundW=0.25; structW=0.11; sentW=0; }
    else if (!hasCapital) { techW=0.25; realW=0.14; confW=0.14; sentW=0.09; fundW=0.27; structW=0.11; capW=0; }

    final rawScore = (technicalScore*techW + capitalScoreValue*capW + sentimentScoreValue*sentW + realtimeScore*realW + confluenceScore*confW + fundamentalScoreValue*fundW + structureScoreValue*structW).clamp(0.0, 10.0);

    final positionFactor = marketPositionFactor ?? 1.0;
    double marketAdjustment = 1.0;
    if (marketContext != null) marketAdjustment = marketContext.getMarketAdjustmentFactor();
    final combinedAdjustment = marketAdjustment * 0.4 + positionFactor * 0.6;

    // 追高惩罚：当日涨幅越高，后续回撤风险越大
    double chasePenalty = 1.0;
    final cp = currentChangePct ?? quote?.changePct;
    if (cp != null && quote != null && quote.price > 0) {
      if (cp > 8) chasePenalty = 0.82;
      else if (cp > 5) chasePenalty = 0.88;
      else if (cp > 3) chasePenalty = 0.94;
      else if (cp > 1.5) chasePenalty = 0.97;
    }

    // 乖离率惩罚：价格偏离均线越远，均值回归风险越大
    double biasPenalty = 1.0;
    final bias = bias6Abs;
    if (bias != null) {
      if (bias > 8) biasPenalty = 0.88;
      else if (bias > 5) biasPenalty = 0.93;
      else if (bias > 3) biasPenalty = 0.97;
    }

    final adjustedScore = (rawScore * combinedAdjustment * chasePenalty * biasPenalty).clamp(0.0, 10.0);

    // ST股票封顶：最高"偏多观望"，防止推荐高风险标的
    final isST = quote != null && isSTStock(quote.name);
    final int totalScore;
    if (isST) {
      totalScore = (adjustedScore * 0.95).round().clamp(1, 5);
    } else {
      totalScore = (adjustedScore * 0.95).round().clamp(1, 10);
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

    // ST股票：仓位建议也基于clamp后的totalScore，避免"观望"+"可积极建仓"矛盾
    final double effectiveScore = isST ? totalScore.toDouble() : adjustedScore;
    double positionAdvice = effectiveScore / 10.0;
    String positionLabel;
    if (effectiveScore >= 8) positionLabel = '可积极建仓';
    else if (effectiveScore >= 6.5) positionLabel = '可适度参与';
    else if (effectiveScore >= 4.5) positionLabel = '中性仓位';
    else if (effectiveScore >= 3) positionLabel = '减仓观望';
    else positionLabel = '不宜参与';

    return ComprehensiveScoreResult(totalScore: totalScore, recommendation: recommendation,
      fundamentalScore: fundamentalScore, newsSentiment: newsSentiment,
      positionAdvice: positionAdvice, positionLabel: positionLabel);
  }
}
