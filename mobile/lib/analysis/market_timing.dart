import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/market_context_provider.dart';
import '../models/stock_models.dart';

class MarketTimingResult {
  final double sentimentScore;
  final String sentimentLabel;
  final String trendDirection;
  final double positionAdvice;
  final String positionLabel;
  final List<String> signals;
  final bool isTradable;

  MarketTimingResult({
    required this.sentimentScore, required this.sentimentLabel,
    required this.trendDirection, required this.positionAdvice,
    required this.positionLabel, required this.signals, required this.isTradable,
  });
}

class MarketTiming {
  /// 获取市场择时结果（含大盘指数 + 涨跌停情绪 + 量能）。
  ///
  /// 统一入口，供 ExploreEngine / OpportunityEngine / SectorPickEngine 共用，
  /// 避免每个引擎重复实现择时获取逻辑。失败时返回 null，调用方应安全降级。
  static Future<MarketTimingResult?> fetchTiming() async {
    try {
      final results = await Future.wait([
        MarketContextProvider.getMarketContext(),
        ApiClient().getMarketSentiment(),
      ]);
      return MarketTiming.analyze(
        marketContext: results[0] as MarketContext?,
        marketSentiment: results[1] as MarketSentiment?,
      );
    } catch (e) {
      debugPrint('[择时] fetchTiming 失败: $e');
      return null;
    }
  }

  static MarketTimingResult analyze({
    required MarketContext? marketContext,
    MarketSentiment? marketSentiment,
  }) {
    final signals = <String>[];

    double indexScore = 1.0;
    if (marketContext != null) {
      final idx = (marketContext.shIndexPct + marketContext.szIndexPct) / 2;
      if (idx > 2.0) { indexScore = 3.0; signals.add('大盘强势上涨${idx.toStringAsFixed(1)}%'); }
      else if (idx > 1.0) { indexScore = 2.5; signals.add('大盘上涨${idx.toStringAsFixed(1)}%'); }
      else if (idx > 0.3) { indexScore = 2.0; }
      else if (idx > -0.3) { indexScore = 1.5; signals.add('大盘窄幅震荡'); }
      else if (idx > -1.0) { indexScore = 1.0; }
      else if (idx > -2.0) { indexScore = 0.5; signals.add('大盘下跌${idx.abs().toStringAsFixed(1)}%'); }
      else { indexScore = 0.0; signals.add('大盘大幅下跌${idx.abs().toStringAsFixed(1)}%'); }
    }

    double breadthScore = 1.0;
    if (marketContext != null && marketContext.upCount > 0 && marketContext.downCount > 0) {
      final total = marketContext.upCount + marketContext.downCount;
      final upRatio = total > 0 ? marketContext.upCount / total : 0.5;
      if (upRatio > 0.7) { breadthScore = 2.0; signals.add('市场普涨'); }
      else if (upRatio > 0.55) breadthScore = 1.5;
      else if (upRatio < 0.3) { breadthScore = 0.0; signals.add('市场普跌'); }
      else if (upRatio < 0.45) breadthScore = 0.5;
    }

    double sentimentComponent = 1.0;
    if (marketSentiment != null) {
      final lu = marketSentiment.limitUpCount, ld = marketSentiment.limitDownCount;
      if (lu > 80 && ld < 10) { sentimentComponent = 2.0; signals.add('涨停家数$lu家，做多情绪高涨'); }
      else if (lu > 50 && ld < 20) sentimentComponent = 1.7;
      else if (lu > 20 && ld < 30) sentimentComponent = 1.3;
      else if (ld > 30 && lu < 30) { sentimentComponent = 0.5; signals.add('跌停家数$ld家，恐慌情绪'); }
      else if (ld > 50) { sentimentComponent = 0.0; signals.add('跌停家数$ld家，极度恐慌'); }
    }

    double premiumScore = 0.8;
    if (marketContext != null) {
      if (marketContext.avgChangePct > 1.0) premiumScore = 1.3;
      else if (marketContext.avgChangePct > 0.3) premiumScore = 1.0;
      else if (marketContext.avgChangePct < -1.0) premiumScore = 0.2;
      else if (marketContext.avgChangePct < -0.3) premiumScore = 0.5;
    }

    double volumeScore = 0.8;
    if (marketSentiment != null && marketSentiment.totalAmountYi > 0) {
      final amt = marketSentiment.totalAmountYi;
      if (amt > 15000) { volumeScore = 1.5; signals.add('两市成交${amt.toStringAsFixed(0)}亿，交投活跃'); }
      else if (amt > 10000) volumeScore = 1.3;
      else if (amt > 7000) volumeScore = 1.0;
      else if (amt > 5000) { volumeScore = 0.6; signals.add('量能不足'); }
      else { volumeScore = 0.3; signals.add('极度缩量'); }
    }

    final totalScore = indexScore * 0.3 + breadthScore * 0.25 + sentimentComponent * 0.2 + premiumScore * 0.15 + volumeScore * 0.1;

    String trendDirection; double positionAdvice; String positionLabel;
    if (totalScore >= 1.8) { trendDirection = 'bull'; positionAdvice = 0.8; positionLabel = '重仓(7-8成)'; signals.add('市场强势，可积极参与'); }
    else if (totalScore >= 1.5) { trendDirection = 'bull'; positionAdvice = 0.6; positionLabel = '偏多仓位(5-6成)'; }
    else if (totalScore >= 1.2) { trendDirection = 'neutral'; positionAdvice = 0.4; positionLabel = '中性仓位(3-4成)'; signals.add('市场震荡，控制仓位'); }
    else if (totalScore >= 0.9) { trendDirection = 'bear'; positionAdvice = 0.2; positionLabel = '轻仓(1-2成)'; signals.add('市场偏弱，减仓观望'); }
    else { trendDirection = 'bear'; positionAdvice = 0.05; positionLabel = '空仓或极轻仓'; signals.add('市场弱势，建议空仓等待'); }

    String sentimentLabel;
    if (totalScore >= 1.6) sentimentLabel = '乐观';
    else if (totalScore >= 1.3) sentimentLabel = '中性偏多';
    else if (totalScore >= 1.0) sentimentLabel = '中性';
    else if (totalScore >= 0.7) sentimentLabel = '谨慎';
    else sentimentLabel = '恐慌';

    return MarketTimingResult(
      sentimentScore: totalScore, sentimentLabel: sentimentLabel,
      trendDirection: trendDirection, positionAdvice: positionAdvice,
      positionLabel: positionLabel, signals: signals, isTradable: totalScore >= 0.9,
    );
  }

  // P2-5修复：clamp至[0.7, 1.0]避免超过1.0导致评分膨胀
  static double getPositionAdjustment(MarketTimingResult timing) =>
      (0.85 + timing.positionAdvice * 0.3).clamp(0.7, 1.0);
}
