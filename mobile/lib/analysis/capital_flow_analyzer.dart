import '../models/stock_models.dart';

class CapitalFlowResult {
  final double score;
  final double mainNetFlow5d;
  final double mainNetFlow10d;
  final double flowTrend;
  final String trendLabel;
  final List<String> signals;
  final double continuityScore;
  final String? accumulationPattern;

  CapitalFlowResult({
    required this.score, required this.mainNetFlow5d, required this.mainNetFlow10d,
    required this.flowTrend, required this.trendLabel, required this.signals,
    this.continuityScore = 0, this.accumulationPattern,
  });
}

class CapitalFlowAnalyzer {
  static CapitalFlowResult analyze({
    required List<HistoryKline> klineData,
    required QuoteData? quote,
  }) {
    final signals = <String>[];
    double score = 5.0;
    double mainNetFlow5d = 0, mainNetFlow10d = 0, flowTrend = 0;

    if (quote != null && (quote.mainNetFlow != 0 || quote.mainNetFlowRate != 0)) {
      final rate = quote.mainNetFlowRate;
      if (rate > 5) { score += 2.0; signals.add('当日主力大幅净流入${rate.toStringAsFixed(1)}%'); }
      else if (rate > 2) { score += 1.2; signals.add('当日主力净流入${rate.toStringAsFixed(1)}%'); }
      else if (rate > 0) { score += 0.5; }
      else if (rate > -3) { score -= 0.5; }
      else if (rate > -6) { score -= 1.0; signals.add('当日主力净流出${rate.abs().toStringAsFixed(1)}%'); }
      else { score -= 1.5; signals.add('当日主力大幅净流出${rate.abs().toStringAsFixed(1)}%'); }
    }

    if (klineData.length >= 11) {
      final last = klineData.last;
      final recent10 = klineData.sublist(klineData.length - 10);
      final recent5 = klineData.sublist(klineData.length - 5);
      final close5dRef = klineData[klineData.length - 6].close;
      final close10dRef = klineData[klineData.length - 11].close;
      final priceChange5d = close5dRef > 0 ? (last.close / close5dRef - 1) * 100 : 0.0;
      final priceChange10d = close10dRef > 0 ? (last.close / close10dRef - 1) * 100 : 0.0;
      final avgVol5 = recent5.map((d) => d.volume).reduce((a, b) => a + b) / 5;
      final avgVol10 = recent10.map((d) => d.volume).reduce((a, b) => a + b) / 10;

      if (priceChange5d > 3 && avgVol5 > avgVol10 * 1.3) { score += 1.0; signals.add('近5日放量上涨，主力做多'); }
      if (priceChange5d < -3 && avgVol5 < avgVol10 * 0.7) { score += 0.5; signals.add('近5日缩量下跌，抛压减轻'); }
      if (priceChange5d < -3 && avgVol5 > avgVol10 * 1.3) { score -= 1.5; signals.add('近5日放量下跌，注意风险'); }
      if (priceChange5d > 5 && avgVol5 < avgVol10 * 0.8 && priceChange10d > 8) { score += 0.8; signals.add('趋势上涨中缩量，主力锁仓'); }
      if (priceChange10d > 5 && priceChange5d < 2 && avgVol5 < avgVol10 * 0.7) { score -= 0.5; signals.add('量价背离：上涨趋势量能衰减'); }

      final obv5ago = klineData[klineData.length - 5].obv;
      if (obv5ago != 0) {
        final obvChange = (last.obv - obv5ago) / obv5ago.abs() * 100;
        if (obvChange > 10) { score += 0.8; signals.add('OBV近5日显著上升'); }
        else if (obvChange > 5) { score += 0.4; }
        else if (obvChange < -10) { score -= 0.8; signals.add('OBV近5日显著下降'); }
        else if (obvChange < -5) { score -= 0.4; }
      }

      // 量能放大因子：近5日均量/近10日均量，>1 表示放量。5日与10日资金流项共用同一量能比。
      // v3.19: 原 volFactor5d/volFactor10d 计算式完全相同（复制粘贴），合并为单一 volFactor。
      final priceFactor5d = priceChange5d / 100.0;
      final volFactor = avgVol10 > 0 ? avgVol5 / avgVol10 : 1.0;
      mainNetFlow5d = priceFactor5d * volFactor * 10;
      mainNetFlow10d = (priceChange10d / 100.0) * volFactor * 10;
      flowTrend = mainNetFlow5d > 0.1 ? 0.7 : mainNetFlow5d > 0.03 ? 0.3 : mainNetFlow5d > -0.03 ? 0 : mainNetFlow5d > -0.1 ? -0.3 : -0.7;
    }

    if (klineData.length >= 20 && klineData.last.volMa5 > 0) {
      final last = klineData.last;
      final recent20 = klineData.sublist(klineData.length - 20);
      final avgVol20 = recent20.map((d) => d.volume).reduce((a, b) => a + b) / 20;
      final volRatio20d = avgVol20 > 0 ? last.volMa5 / avgVol20 : 1.0;
      if (volRatio20d > 2.0) { score += 0.5; signals.add('成交量活跃'); }
      else if (volRatio20d < 0.5) { score -= 0.5; signals.add('成交量低迷'); }
    }

    if (klineData.length >= 15) {
      final recent15 = klineData.sublist(klineData.length - 15);
      final refClose15d = recent15.first.close;
      final priceChange15d = refClose15d > 0 ? (klineData.last.close / refClose15d - 1) * 100 : 0.0;
      if (priceChange15d < -8) {
        final recent3 = klineData.sublist(klineData.length - 3);
        final recent3to6 = klineData.sublist(klineData.length - 6, klineData.length - 3);
        final avgVol3 = recent3.map((d) => d.volume).reduce((a, b) => a + b) / 3;
        final avgVol3to6 = recent3to6.map((d) => d.volume).reduce((a, b) => a + b) / 3;
        final priceStable = recent3.first.close > 0
            ? (recent3.last.close / recent3.first.close - 1).abs() < 1.5
            : false;
        if (avgVol3 > avgVol3to6 * 1.2 && priceStable) { score += 1.2; signals.add('跌幅后缩量企稳放量，吸筹迹象'); }
      }
      if (priceChange15d > 15) {
        final recent5 = klineData.sublist(klineData.length - 5);
        final early10 = klineData.sublist(klineData.length - 15, klineData.length - 5);
        final avgVol5 = recent5.map((d) => d.volume).reduce((a, b) => a + b) / 5;
        final avgVolEarly10 = early10.map((d) => d.volume).reduce((a, b) => a + b) / 10;
        if (avgVol5 < avgVolEarly10 * 0.6) { score -= 1.0; signals.add('大涨后缩量，主力派发迹象'); }
      }
    }

    String tl = '资金流向平衡';
    if (flowTrend > 0.5) tl = '资金持续流入';
    else if (flowTrend > 0.1) tl = '资金温和流入';
    else if (flowTrend < -0.5) tl = '资金持续流出';
    else if (flowTrend < -0.1) tl = '资金温和流出';

    double contScore = 0;
    String? accumPattern;
    if (klineData.length >= 5) {
      final recent5 = klineData.sublist(klineData.length - 5);
      int consecutiveInflow = 0;
      int consecutiveOutflow = 0;
      for (final k in recent5.reversed) {
        final isInflow = k.close > k.open && k.volume > (k.volMa5 > 0 ? k.volMa5 : k.volume);
        final isOutflow = k.close < k.open && k.volume > (k.volMa5 > 0 ? k.volMa5 : k.volume);
        if (isInflow && consecutiveOutflow == 0) consecutiveInflow++;
        else if (isOutflow && consecutiveInflow == 0) consecutiveOutflow++;
        else break;
      }
      if (consecutiveInflow >= 5) { contScore = 2.5; signals.add('连续5日主力净流入'); }
      else if (consecutiveInflow >= 3) { contScore = 1.5; signals.add('连续${consecutiveInflow}日主力净流入'); }
      else if (consecutiveInflow >= 2) { contScore = 0.8; signals.add('连续2日主力净流入'); }
      if (consecutiveOutflow >= 5) { contScore = -2.5; signals.add('连续5日主力净流出'); }
      else if (consecutiveOutflow >= 3) { contScore = -1.5; signals.add('连续${consecutiveOutflow}日主力净流出'); }
      else if (consecutiveOutflow >= 2) { contScore = -0.8; signals.add('连续2日主力净流出'); }
      score += contScore;

      if (klineData.length >= 20) {
        final recent20 = klineData.sublist(klineData.length - 20);
        final high20 = recent20.map((k) => k.high).reduce((a, b) => a > b ? a : b);
        final low20 = recent20.map((k) => k.low).reduce((a, b) => a < b ? a : b);
        final range20 = low20 > 0 ? (high20 - low20) / low20 : 0.0;
        final upVol = recent20.where((k) => k.close > k.open).map((k) => k.volume).fold(0.0, (a, b) => a + b);
        final downVol = recent20.where((k) => k.close <= k.open).map((k) => k.volume).fold(0.0, (a, b) => a + b);
        final obvRising = klineData.last.obv > klineData[klineData.length - 5].obv;
        if (range20 < 0.10 && upVol > downVol && obvRising) {
          score += 1.2; signals.add('横盘吸筹：20日振幅${(range20 * 100).toStringAsFixed(1)}%+OBV上升');
          accumPattern = 'sideways';
        }
      }

      if (klineData.length >= 5) {
        final last3 = klineData.sublist(klineData.length - 3);
        final allDown = last3.every((k) => k.close < k.open);
        final volDeclining = last3.length >= 2 && last3[0].volume >= last3[1].volume && last3[1].volume >= last3[2].volume;
        final obvNotDeclining = klineData.last.obv >= klineData[klineData.length - 3].obv;
        if (allDown && volDeclining && obvNotDeclining) {
          score += 1.0; signals.add('打压吸筹：连续阴线+量递减+OBV不降');
          accumPattern = 'smash';
        }
      }
    }

    score = score.clamp(0.0, 10.0);
    return CapitalFlowResult(score: score, mainNetFlow5d: mainNetFlow5d, mainNetFlow10d: mainNetFlow10d,
        flowTrend: flowTrend, trendLabel: tl, signals: signals,
        continuityScore: contScore, accumulationPattern: accumPattern);
  }
}
