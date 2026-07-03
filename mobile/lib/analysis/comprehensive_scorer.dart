import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';
import 'market_structure_analyzer.dart';
import 'sector_heat_detector.dart';
import 'sector_rotation.dart';

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

  /// 7维度加权（v2.37 评审微调）：技术33%+资金18%+实时16%+共振12%+情绪10%+基本面7%+结构4%
  /// v2.30: 新增 data/industryRSScore/adxValue/isBullAlign 参数用于动量保护和行业RS
  /// v2.38.0: 新增 sectorName/sectorAnalysis 参数用于板块情绪过热检测
  static ComprehensiveScoreResult combine({
    required double technicalScore, required double realtimeScore, required double confluenceScore,
    double? capitalFlowScore, double? marketPositionFactor,
    required QuoteData? quote, required MarketContext? marketContext, required List<dynamic>? newsList,
    MarketStructureResult? marketStructure,
    double? currentChangePct,
    double? bias6,
    List<HistoryKline>? data,
    double? industryRSScore,
    double? adxValue,
    bool? isBullAlign,
    String? sectorName,
    List<SectorAnalysis>? sectorAnalysis,
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
    // v2.35: 调整为短线导向权重 — 基本面是慢变量，对短线(1-3日)预测贡献低，
    //        降低基本面/结构权重，提升技术/资金/实时/情绪权重，使评分与留档胜率评估周期匹配
    // v2.37: 评分评审后微调 — 结构2%→4%(ADX/MA布局对短线择时影响显著)，
    //        基本面5%→7%(避免极端高估低估个股被短线信号掩盖)，技术35%→33%、实时18%→16%(等比例让出)
    double techW=0.33, capW=0.18, realW=0.16, confW=0.12, sentW=0.10, fundW=0.07, structW=0.04;
    final hasFund = fundamentalScore != null, hasSent = newsSentiment != null, hasCapital = capitalFlowScore != null;
    if (!hasFund && !hasSent && !hasCapital) { techW=0.50; realW=0.25; confW=0.18; structW=0.07; capW=sentW=fundW=0; }
    else if (!hasFund && !hasSent) { techW=0.40; capW=0.22; realW=0.19; confW=0.14; structW=0.05; sentW=fundW=0; }
    else if (!hasFund) { techW=0.35; capW=0.20; realW=0.17; confW=0.13; sentW=0.11; structW=0.04; fundW=0; }
    else if (!hasSent) { techW=0.37; capW=0.20; realW=0.18; confW=0.13; fundW=0.08; structW=0.04; sentW=0; }
    else if (!hasCapital) { techW=0.40; realW=0.20; confW=0.15; sentW=0.12; fundW=0.09; structW=0.04; capW=0; }

    // v2.30: 熊市基本面权重提升 — 下跌市中低估值防守价值更大
    if (marketContext != null && marketContext.avgChangePct < -0.5 && fundW > 0) {
      final originalFundW = fundW; // 保存原始权重用于正确比例缩放
      fundW *= 1.3;
      // 从其他维度按比例扣除以保持总和为 1.0
      final scaleFactor = (1.0 - fundW) / (1.0 - originalFundW);
      techW *= scaleFactor; capW *= scaleFactor; realW *= scaleFactor;
      confW *= scaleFactor; sentW *= scaleFactor; structW *= scaleFactor;
    }

    var rawScore = (technicalScore*techW + capitalScoreValue*capW + sentimentScoreValue*sentW + realtimeScore*realW + confluenceScore*confW + fundamentalScoreValue*fundW + structureScoreValue*structW).clamp(0.0, 10.0);

    // v2.30: 行业RS折扣 — 行业内排名靠后的"强信号"是补涨陷阱
    if (industryRSScore != null && industryRSScore < 0.30) {
      rawScore *= 0.90;
    }

    final positionFactor = marketPositionFactor ?? 1.0;
    double marketAdjustment = 1.0;
    if (marketContext != null) marketAdjustment = marketContext.getMarketAdjustmentFactor();
    final combinedAdjustment = marketAdjustment * 0.4 + positionFactor * 0.6;

    // v2.30: 动量保护因子 — ADX>30且多头排列时降低惩罚，避免压制牛股
    final effectiveAdx = adxValue ?? (marketStructure?.adxValue ?? 25);
    final effectiveBullAlign = isBullAlign ?? (marketStructure?.maAlignment == '多头');
    final momentumFactor = _momentumProtectionFactor(data, effectiveAdx, effectiveBullAlign);

    // 追高惩罚：当日涨幅越高，后续回撤风险越大
    // v2.30: 动量保护 + 连涨天数判断（突破首日减轻惩罚）
    // v2.38.0: 涨停股(cp>9.5%)不被动量保护削弱，避免追高风险被掩盖
    double chasePenalty = 1.0;
    final cp = currentChangePct ?? quote?.changePct;
    if (cp != null && quote != null && quote.price > 0) {
      final consecutiveRise = _consecutiveRiseDays(data);
      if (cp > 9.5) chasePenalty = 0.80;
      else if (cp > 8) chasePenalty = consecutiveRise >= 3 ? 0.82 : 0.90;
      else if (cp > 5) chasePenalty = consecutiveRise >= 3 ? 0.88 : 0.94;
      else if (cp > 3) chasePenalty = consecutiveRise >= 2 ? 0.94 : 0.97;
      else if (cp > 1.5) chasePenalty = 0.97;
      if (cp <= 9.5) {
        chasePenalty = 1.0 - (1.0 - chasePenalty) * momentumFactor;
      }
    }

    // 乖离率惩罚：价格偏离均线越远，均值回归风险越大
    // v2.30: 动量保护 — 强势趋势中惩罚减半
    double biasPenalty = 1.0;
    if (bias6 != null) {
      final biasAbs = bias6.abs();
      final isOversold = bias6 < 0;
      if (biasAbs > 8) biasPenalty = isOversold ? 0.94 : 0.88;
      else if (biasAbs > 5) biasPenalty = isOversold ? 0.97 : 0.93;
      else if (biasAbs > 3) biasPenalty = isOversold ? 0.99 : 0.97;
      // v2.30: 动量保护
      biasPenalty = 1.0 - (1.0 - biasPenalty) * momentumFactor;
    }

    final adjustedScore = (rawScore * combinedAdjustment * chasePenalty * biasPenalty).clamp(0.0, 10.0);

    // v2.38.0: 加回温和系数0.97，减少borderline评分过度集中在6分（谨慎买入）
    //          之前移除0.95后，5.5→6、6.5→7，导致6分股票过多（89只/204只）
    //          使用0.97而非0.95，平衡评分分布和真实度：5.5→5.335→5，6.5→6.305→6
    var temperedScore = adjustedScore * 0.97;

    // v2.38.0: 板块情绪过热检测 — 过热板块个股评分乘以0.85折扣
    if (sectorName != null && sectorAnalysis != null && sectorAnalysis.isNotEmpty) {
      final heatDiscount = SectorHeatDetector.getHeatDiscount(sectorName, sectorAnalysis);
      if (heatDiscount < 1.0) {
        temperedScore *= heatDiscount;
      }
    }

    // ST股票封顶：最高"偏多观望"，防止推荐高风险标的
    final isST = quote != null && isSTStock(quote.name);
    final int totalScore;
    if (isST) {
      totalScore = temperedScore.round().clamp(1, 5);
    } else {
      totalScore = temperedScore.round().clamp(1, 10);
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

    final double effectiveScore = isST ? totalScore.toDouble() : temperedScore;
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

  /// v2.30: 动量保护因子
  /// 当 ADX > 30 且均线多头排列时，趋势动量强劲，惩罚应减半
  static double _momentumProtectionFactor(List<HistoryKline>? data, double adx, bool isBullAlign) {
    if (adx > 30 && isBullAlign) {
      // 额外检查：确认是放量突破确认的趋势，而非缩量虚涨
      if (data != null && data.length >= 3) {
        final last = data.last;
        final prev = data[data.length - 2];
        final volIncreasing = last.volume > prev.volume;
        final priceMomentum = last.close > prev.close;
        if (volIncreasing && priceMomentum) return 0.5; // 放量上涨 = 真正动量
        return 0.7; // 多头排列但无量，部分保护
      }
      return 0.5;
    }
    return 1.0; // 无动量保护
  }

  /// v2.30: 计算连涨天数（用于判断是否追高）
  static int _consecutiveRiseDays(List<HistoryKline>? data) {
    if (data == null || data.length < 2) return 0;
    int count = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i].close > data[i].open && data[i].changePct > 0) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }
}
