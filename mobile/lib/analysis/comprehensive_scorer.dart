import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';
import 'market_structure_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import 'sector_heat_detector.dart';
import 'sector_rotation.dart';
import 'sector_momentum_calculator.dart';

class ComprehensiveScoreResult {
  final int totalScore;
  final String recommendation;
  final FundamentalScore? fundamentalScore;
  final NewsSentiment? newsSentiment;
  final double positionAdvice;
  final String positionLabel;
  final double chaseRiskFactor;
  final double marketFactor;
  final double predictionModifier;
  final double sectorMomentumScore;

  ComprehensiveScoreResult({required this.totalScore, required this.recommendation,
    this.fundamentalScore, this.newsSentiment, this.positionAdvice=0.5, this.positionLabel='中性仓位',
    this.chaseRiskFactor=1.0, this.marketFactor=1.0, this.predictionModifier=1.0, this.sectorMomentumScore=0});
}

class ComprehensiveScorer {
  /// 7维权重常量（v2.37 评审微调）
  /// 技术面33% + 资金面18% + 实时16% + 共振12% + 情绪10% + 基本面7% + 结构4%
  /// 评分解释页和 combine() 共用，确保展示与实际计算一致
  static const double techWeight = 0.33;
  static const double capWeight = 0.18;
  static const double realWeight = 0.16;
  static const double confWeight = 0.12;
  static const double sentWeight = 0.10;
  static const double fundWeight = 0.07;
  static const double structWeight = 0.04;

  static const double stTechWeight = 0.35;
  static const double stCapWeight = 0.22;
  static const double stRealWeight = 0.18;
  static const double stConfWeight = 0.10;
  static const double stSectorWeight = 0.10;
  static const double stStructWeight = 0.05;

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
    String preferredDuration = 'mediumTerm',
    IntradayProfile? intradayProfile,
    NextDayPredictionResult? nextDayPrediction,
    NextSessionPrediction? nextSessionPrediction,
    SectorMomentumResult? sectorMomentum,
  }) {
    FundamentalScore? fundamentalScore;
    double fundamentalScoreValue = 5.0;
    if (quote != null && quote.price > 0) {
      // v4.3: ROE now threaded from QuoteData (nullable; analyzer falls back to 5.0 when null)
      fundamentalScore = FundamentalAnalyzer.analyze(quote, roe: quote.roe);
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
    final isShortTerm = preferredDuration == 'shortTerm';
    double techW, capW, realW, confW, sentW, fundW, structW, sectorW;
    if (isShortTerm) {
      techW=stTechWeight; capW=stCapWeight; realW=stRealWeight; confW=stConfWeight; sentW=0; fundW=0; structW=stStructWeight; sectorW=stSectorWeight;
    } else {
      techW=techWeight; capW=capWeight; realW=realWeight; confW=confWeight; sentW=sentWeight; fundW=fundWeight; structW=structWeight; sectorW=0;
    }
    final hasFund = fundamentalScore != null, hasSent = newsSentiment != null, hasCapital = capitalFlowScore != null;
    if (isShortTerm) {
      if (!hasCapital) { techW += 0.05; realW += 0.05; capW = 0; }
    } else {
      if (!hasFund && !hasSent && !hasCapital) { techW=0.50; realW=0.25; confW=0.18; structW=0.07; capW=sentW=fundW=sectorW=0; }
      else if (!hasFund && !hasSent) { techW=0.40; capW=0.22; realW=0.19; confW=0.14; structW=0.05; sentW=fundW=sectorW=0; }
      else if (!hasFund) { techW=0.35; capW=0.20; realW=0.17; confW=0.13; sentW=0.11; structW=0.04; fundW=sectorW=0; }
      else if (!hasSent) { techW=0.37; capW=0.20; realW=0.18; confW=0.13; fundW=0.08; structW=0.04; sentW=sectorW=0; }
      else if (!hasCapital) { techW=0.40; realW=0.20; confW=0.15; sentW=0.12; fundW=0.09; structW=0.04; capW=sectorW=0; }
    }

    // v2.30: 熊市基本面权重提升 — 下跌市中低估值防守价值更大
    if (marketContext != null && marketContext.avgChangePct < -0.5 && fundW > 0) {
      final originalFundW = fundW; // 保存原始权重用于正确比例缩放
      fundW *= 1.3;
      // 从其他维度按比例扣除以保持总和为 1.0
      final scaleFactor = (1.0 - fundW) / (1.0 - originalFundW);
      techW *= scaleFactor; capW *= scaleFactor; realW *= scaleFactor;
      confW *= scaleFactor; sentW *= scaleFactor; structW *= scaleFactor; sectorW *= scaleFactor;
    }

    final sectorMomentumScore = sectorMomentum?.score ?? 0.0;
    final sectorMomentumMapped = (sectorMomentumScore + 1.0) * 5.0;
    var rawScore = (technicalScore*techW + capitalScoreValue*capW + sentimentScoreValue*sentW + realtimeScore*realW + confluenceScore*confW + fundamentalScoreValue*fundW + structureScoreValue*structW + sectorMomentumMapped*sectorW).clamp(0.0, 10.0);

    if (isShortTerm && intradayProfile != null) {
      final blendedRealtime = realtimeScore * 0.5 + intradayProfile.intradayScore * 0.5;
      rawScore = (technicalScore*techW + capitalScoreValue*capW + sentimentScoreValue*sentW + blendedRealtime*realW + confluenceScore*confW + fundamentalScoreValue*fundW + structureScoreValue*structW + sectorMomentumMapped*sectorW).clamp(0.0, 10.0);
    }

    if (sectorMomentum != null) {
      rawScore *= sectorMomentum.mainLineBonus;
      rawScore *= sectorMomentum.retreatDiscount;
    }

    // v2.30: 行业RS折扣 — 行业内排名靠后的"强信号"是补涨陷阱
    if (industryRSScore != null && industryRSScore < 0.30) {
      rawScore *= 0.90;
    }

    final effectiveAdx = adxValue ?? (marketStructure?.adxValue ?? 25);
    final effectiveBullAlign = isBullAlign ?? (marketStructure?.maAlignment == '多头');
    final momentumFactor = _momentumProtectionFactor(data, effectiveAdx, effectiveBullAlign);

    // Layer 1: chaseRiskFactor [0.40, 1.0] — chase penalty + bias penalty + trend consistency
    double chaseP = 1.0;
    final cp = currentChangePct ?? quote?.changePct;
    if (cp != null && quote != null && quote.price > 0) {
      final consecutiveRise = _consecutiveRiseDays(data);
      if (cp > 9.5) chaseP = 0.65;
      else if (cp > 8) chaseP = 0.75;
      else if (cp > 5 && consecutiveRise >= 3) chaseP = 0.92;
      if (cp > 5) {
        chaseP = 1.0 - (1.0 - chaseP) * momentumFactor;
      }
    }
    double biasP = 1.0;
    if (bias6 != null) {
      final biasAbs = bias6.abs();
      final isOversold = bias6 < 0;
      if (biasAbs > 8) biasP = isOversold ? 0.94 : 0.88;
      else if (biasAbs > 5) biasP = isOversold ? 0.97 : 0.93;
      else if (biasAbs > 3) biasP = isOversold ? 0.99 : 0.97;
      biasP = 1.0 - (1.0 - biasP) * momentumFactor;
    }
    double trendP = 1.0;
    if (data != null && data.length >= 3 && rawScore >= 5.5) {
      final recentChange = (data.last.close - data[data.length - 3].close) / data[data.length - 3].close * 100;
      if (recentChange < -5) trendP = 0.70;
      else if (recentChange < -3) trendP = 0.82;
    }
    final chaseRiskFactor = (chaseP * biasP * trendP).clamp(0.40, 1.0);

    // Layer 2: marketFactor [0.50, 1.0] — market adjustment + decline discount + heat discount + finance discount
    double marketFactor = 1.0;
    final positionFactor = marketPositionFactor ?? 1.0;
    double marketAdjustment = 1.0;
    if (marketContext != null) marketAdjustment = marketContext.getMarketAdjustmentFactor();
    marketFactor *= (marketAdjustment * 0.4 + positionFactor * 0.6);
    if (marketContext != null && quote != null && !isSTStock(quote.name)) {
      final acp = marketContext.avgChangePct;
      double declineFactor = 1.0;
      if (acp <= -3.0) declineFactor = 0.80;
      else if (acp <= -2.0) declineFactor = 0.87;
      else if (acp <= -1.0) declineFactor = 0.93;
      else if (acp <= -0.5) declineFactor = 0.97;
      if (declineFactor < 1.0) {
        final stockAlpha = (quote.changePct - acp);
        if (stockAlpha > 2.0) {
          // 逆市大幅跑赢，不折扣
        } else if (stockAlpha > 0) {
          declineFactor = 1.0 - (1.0 - declineFactor) * 0.5;
        }
        marketFactor *= declineFactor;
      }
    }
    if (sectorName != null && sectorAnalysis != null && sectorAnalysis.isNotEmpty) {
      final heatDiscount = SectorHeatDetector.getHeatDiscount(sectorName, sectorAnalysis);
      if (heatDiscount < 1.0) marketFactor *= heatDiscount;
    }
    if (quote != null && _isHighBetaFinance(quote.name)) {
      marketFactor *= 0.88;
    }
    marketFactor = marketFactor.clamp(0.50, 1.0);

    // Layer 3: predictionModifier [0.85, 1.05]
    double predictionModifierValue = 1.0;
    if (nextDayPrediction != null && nextDayPrediction.sampleCount >= 15) {
      if (nextDayPrediction.downProbability > 0.60) {
        predictionModifierValue *= 0.85;
      } else if (nextDayPrediction.upProbability > 0.60) {
        predictionModifierValue *= 1.05;
      }
    }
    if (nextSessionPrediction != null && nextSessionPrediction.confidence > 0.5) {
      if (nextSessionPrediction.downsideRiskProbability > 0.55) {
        predictionModifierValue *= 0.90;
      }
    }

    var temperedScore = rawScore * chaseRiskFactor * marketFactor * predictionModifierValue;
    final totalPenalty = chaseRiskFactor * marketFactor * predictionModifierValue;
    if (totalPenalty < 0.40) {
      temperedScore = rawScore * 0.40;
    }
    temperedScore = temperedScore.clamp(0.0, 10.0);

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
      positionAdvice: positionAdvice, positionLabel: positionLabel,
      chaseRiskFactor: chaseRiskFactor, marketFactor: marketFactor,
      predictionModifier: predictionModifierValue, sectorMomentumScore: sectorMomentumScore);
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

  /// v3.2: 高Beta金融板块检测 — 券商/银行/保险股与大盘高度联动
  static bool _isHighBetaFinance(String name) {
    return name.contains('证券') ||
           name.contains('银行') ||
           name.contains('保险');
  }
}
