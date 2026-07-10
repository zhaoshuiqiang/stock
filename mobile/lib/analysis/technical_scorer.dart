import '../models/stock_models.dart';

class TechnicalScoreResult {
  final double signalScore;
  final double trendScore;
  final double momentumScore;
  final double volumeScore;
  final double volatilityScore;
  final double totalScore;

  TechnicalScoreResult({
    required this.signalScore,
    required this.trendScore,
    required this.momentumScore,
    required this.volumeScore,
    required this.volatilityScore,
    required this.totalScore,
  });
}

class TechnicalScorer {
  static TechnicalScoreResult score(
    List<HistoryKline> data,
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
  ) {
    if (data.isEmpty) {
      return TechnicalScoreResult(
        signalScore: 1.5, trendScore: 1.0, momentumScore: 1.0,
        volumeScore: 0.75, volatilityScore: 1.0, totalScore: 5.0,
      );
    }
    final signalScore = _scoreSignal(data, buySignals, sellSignals);
    final trendScore = _scoreTrend(data);
    final momentumScore = _scoreMomentum(data);
    final volumeScore = _scoreVolume(data);
    final volatilityScore = _scoreVolatility(data);

    final totalScore =
        (signalScore + trendScore + momentumScore + volumeScore + volatilityScore)
            .clamp(0.0, 10.0);

    return TechnicalScoreResult(
      signalScore: signalScore,
      trendScore: trendScore,
      momentumScore: momentumScore,
      volumeScore: volumeScore,
      volatilityScore: volatilityScore,
      totalScore: totalScore,
    );
  }

  /// 1. 信号评分 (0-3分) - 按信号强度加权
  /// v2.60.0: 新增买入信号数量惩罚 — 买入信号过多(>=3)时降低评分，
  ///         因为数据分析显示买入信号越多胜率越低(>=5仅33.3%)
  static double _scoreSignal(
    List<HistoryKline> data,
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
  ) {
    final last = data[data.length - 1];
    final adx = last.adx14;
    final weightedStrength =
        _calculateWeightedSignalStrength(buySignals, sellSignals, adx);
    final buyStrength = weightedStrength.$1;
    final sellStrength = weightedStrength.$2;
    final totalStrength = buyStrength + sellStrength;
    final maxTotal =
        totalStrength > 0 ? (totalStrength * 0.6).clamp(30.0, 150.0) : 150.0;
    double signalRaw = (buyStrength - sellStrength) / maxTotal * 3;
    signalRaw = signalRaw.clamp(-3.0, 3.0);

    // v2.60.0: 买入信号数量惩罚 — 信号过多意味着可能过度拟合或信号冲突
    // 数据表明：买入信号>=5胜率33.3%，>=3胜率38.4%，远低于平均水平
    final buySignalCount = buySignals.length;
    if (buySignalCount >= 5) {
      signalRaw *= 0.6;
    } else if (buySignalCount >= 4) {
      signalRaw *= 0.75;
    } else if (buySignalCount >= 3) {
      signalRaw *= 0.88;
    }

    double signalScore = (signalRaw + 3.0) / 2.0;
    return signalScore;
  }

  /// 2. 趋势强度评分 (0-2分) - 基于均线排列 + ADX趋势强度
  /// v2.38.0: 降低均线多头排列权重(1.8→1.4)，增加MA20偏离保护，防止追高
  /// v2.48.0: 增加日内暴跌惩罚 + 趋势强度加分需确认价格在MA上方
  static double _scoreTrend(List<HistoryKline> data) {
    final last = data[data.length - 1];
    double trendScore = 0;
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
        trendScore = 1.4;
        if (last.close > 0) {
          final ma20Deviation = (last.close - last.ma20) / last.ma20 * 100;
          if (ma20Deviation > 8) {
            trendScore *= 0.85;
          } else if (ma20Deviation > 5) {
            trendScore *= 0.92;
          }
        }
        // v2.48.0: 日内暴跌惩罚 — 收盘价较开盘价下跌>5%时大幅降低趋势分
        // 防止均线多头但当日暴跌的股票获得虚高评分
        if (last.open > 0) {
          final intradayChange = (last.close - last.open) / last.open * 100;
          if (intradayChange < -5) {
            trendScore *= 0.6;
          } else if (intradayChange < -3) {
            trendScore *= 0.8;
          }
        }
      } else if (last.ma5 > last.ma10) {
        trendScore = 1.1;
      } else if (last.ma5 > last.ma20) {
        trendScore = 0.7;
      } else {
        trendScore = 0.3;
      }
    }
    final isBearishAlignment = last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0
        && last.ma5 < last.ma10 && last.ma10 < last.ma20;
    if (isBearishAlignment) {
      trendScore = 0;
    }
    // ADX 趋势强度加成：仅在非空头排列且价格在MA5上方时给予奖励
    // v2.48.0: 增加价格位置确认，避免强趋势下跌(ADX>25+价格在MA下方)获得趋势加分
    final priceAboveMa5 = last.close > 0 && last.ma5 > 0 && last.close > last.ma5;
    if (!isBearishAlignment && last.adx14 > 25 && priceAboveMa5) {
      trendScore += 0.5;
    } else if (last.adx14 > 0 && last.adx14 < 20) {
      trendScore -= 0.3;
    }
    trendScore = trendScore.clamp(0.0, 2.0);
    return trendScore;
  }

  /// 3. 动量评分 (0-2分) - 基于RSI + BIAS乖离率
  static double _scoreMomentum(List<HistoryKline> data) {
    final last = data[data.length - 1];
    double momentumScore = 1.0;
    if (last.rsi6 > 0) {
      final isTrending = last.adx14 > 25;
      final isRanging = last.adx14 > 0 && last.adx14 < 20;
      if (isTrending) {
        if (last.rsi6 >= 60) {
          momentumScore = 1.8;
        } else if (last.rsi6 >= 50) {
          momentumScore = 1.3;
        } else if (last.rsi6 >= 40) {
          momentumScore = 0.8;
        } else {
          momentumScore = 0.3;
        }
      } else if (isRanging) {
        if (last.rsi6 < 30) {
          momentumScore = 1.6;
        } else if (last.rsi6 < 40) {
          momentumScore = 1.3;
        } else if (last.rsi6 <= 60) {
          momentumScore = 1.0;
        } else if (last.rsi6 <= 70) {
          momentumScore = 0.7;
        } else {
          momentumScore = 0.3;
        }
      } else {
        if (last.rsi6 < 30) {
          momentumScore = 1.4;
        } else if (last.rsi6 < 40) {
          momentumScore = 1.2;
        } else if (last.rsi6 < 60) {
          momentumScore = 1.0;
        } else if (last.rsi6 < 70) {
          momentumScore = 0.8;
        } else {
          momentumScore = 0.5;
        }
      }
    }
    if (last.bias6.abs() > 5) {
      momentumScore -= 0.4;
    } else if (last.bias6.abs() > 3) {
      momentumScore -= 0.2;
    }
    momentumScore = momentumScore.clamp(0.0, 2.0);
    return momentumScore;
  }

  /// 4. 量价确认评分 (0-1.5分) - 基于量比 + OBV趋势
  static double _scoreVolume(List<HistoryKline> data) {
    final last = data[data.length - 1];
    double volumeScore = 0.8;
    if (last.volMa5 > 0) {
      final volRatio = last.volume / last.volMa5;
      if (last.close >= last.open) {
        if (volRatio > 1.5) {
          volumeScore = 1.4;
        } else if (volRatio > 1.0) {
          volumeScore = 1.1;
        } else {
          volumeScore = 0.6;
        }
      } else {
        if (volRatio > 1.5) {
          volumeScore = 0.2;
        } else if (volRatio > 1.0) {
          volumeScore = 0.5;
        } else {
          volumeScore = 0.8;
        }
      }
    }
    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (obv5 != 0) {
        if (last.obv > obv5 && last.close > data[data.length - 5].close) {
          volumeScore += 0.3;
        } else if (last.obv < obv5 && last.close < data[data.length - 5].close) {
          volumeScore -= 0.2;
        }
      }
    }
    volumeScore = volumeScore.clamp(0.0, 1.5);
    return volumeScore;
  }

  /// 5. 波动率评分 (0-1.5分) - 基于ATR
  static double _scoreVolatility(List<HistoryKline> data) {
    final last = data[data.length - 1];
    double volatilityScore = 0.8;
    if (last.atr14 > 0 && last.close > 0) {
      final atrPct = last.atr14 / last.close * 100;
      if (atrPct < 1) {
        volatilityScore = 0.3;
      } else if (atrPct < 2) {
        volatilityScore = 0.7;
      } else if (atrPct < 3) {
        volatilityScore = 1.1;
      } else if (atrPct < 5) {
        volatilityScore = 1.3;
      } else if (atrPct < 8) {
        volatilityScore = 0.8;
      } else {
        volatilityScore = 0.3;
      }
    }
    return volatilityScore;
  }

  /// ADX趋势/盘整权重调整：在加权阶段分别调整信号强度
  static (double buyStrength, double sellStrength) _calculateWeightedSignalStrength(
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
    double adx,
  ) {
    double buyStrength = 0;
    double sellStrength = 0;
    for (final s in buySignals) {
      double strength = s.strength.toDouble();

      if (s.signal.contains('预警')) {
        strength *= 0.5;
      }

      if (adx > 25) {
        if (s.indicator == 'MA' ||
            s.indicator == 'MACD' ||
            s.signal.contains('排列') ||
            s.signal.contains('金叉') ||
            s.signal.contains('死叉')) {
          strength *= 1.2;
        }
      } else if (adx > 0 && adx < 20) {
        if (s.indicator == 'RSI' ||
            s.indicator == 'KDJ' ||
            s.signal.contains('超买') ||
            s.signal.contains('超卖')) {
          strength *= 1.2;
        }
      }
      buyStrength += strength;
    }
    for (final s in sellSignals) {
      double strength = s.strength.toDouble();

      if (s.signal.contains('预警')) {
        strength *= 0.5;
      }

      if (adx > 25) {
        if (s.indicator == 'MA' ||
            s.indicator == 'MACD' ||
            s.signal.contains('排列') ||
            s.signal.contains('金叉') ||
            s.signal.contains('死叉')) {
          strength *= 1.2;
        }
      } else if (adx > 0 && adx < 20) {
        if (s.indicator == 'RSI' ||
            s.indicator == 'KDJ' ||
            s.signal.contains('超买') ||
            s.signal.contains('超卖')) {
          strength *= 1.2;
        }
      }
      sellStrength += strength;
    }
    return (buyStrength, sellStrength);
  }
}
