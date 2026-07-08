import '../models/stock_models.dart';

/// Result of short-term tradeability scoring.
class ShortTermScoreResult {
  final double score;
  final int maxRecommendationScore;
  final String actionLabel;
  final List<String> positiveFactors;
  final List<String> riskCaps;

  const ShortTermScoreResult({
    required this.score,
    required this.maxRecommendationScore,
    required this.actionLabel,
    this.positiveFactors = const [],
    this.riskCaps = const [],
  });
}

/// Scores whether a stock is suitable for a 1-10 trading day operation.
///
/// This intentionally differs from the comprehensive score: slow variables such
/// as valuation are treated as risk caps, while signal freshness, volume-price
/// quality, realtime flow, and chase risk dominate the score.
class ShortTermScorer {
  static ShortTermScoreResult score({
    required List<HistoryKline> data,
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    QuoteData? quote,
  }) {
    if (data.isEmpty) {
      return const ShortTermScoreResult(
        score: 4,
        maxRecommendationScore: 5,
        actionLabel: '短线回避',
        riskCaps: ['短线数据不足'],
      );
    }

    final last = data.last;
    var raw = 5.0;
    var maxRecommendationScore = 10;
    final positives = <String>[];
    final risks = <String>[];

    final buyStrength = _weightedStrength(buySignals);
    final sellStrength = _weightedStrength(sellSignals);
    if (buyStrength > sellStrength) {
      raw += ((buyStrength - sellStrength) * 0.45).clamp(0.0, 2.0);
      positives.add('短线买入信号占优');
    } else if (sellStrength > buyStrength) {
      raw -= ((sellStrength - buyStrength) * 0.7).clamp(0.0, 2.8);
      risks.add('短线卖出信号占优');
    }

    raw += _scoreRecentPrice(data, positives, risks);
    raw += _scoreVolumePrice(data, positives, risks);
    raw += _scoreQuote(quote, positives, risks);
    raw += _scoreVolatility(last, quote, risks);

    if (quote != null) {
      final cap = _riskCapFromQuote(quote, data, risks);
      if (cap < maxRecommendationScore) maxRecommendationScore = cap;
    }

    if (raw < 4.5) {
      maxRecommendationScore = _lowerCap(maxRecommendationScore, 4);
    } else if (raw < 5.5) {
      maxRecommendationScore = _lowerCap(maxRecommendationScore, 5);
    } else if (raw < 6.5) {
      maxRecommendationScore = _lowerCap(maxRecommendationScore, 6);
    }

    final capped = raw.clamp(0.0, maxRecommendationScore.toDouble()).toDouble();
    final actionLabel = capped >= 7
        ? '短线可参与'
        : capped >= 5
            ? '短线轻仓观察'
            : '短线回避';

    return ShortTermScoreResult(
      score: capped,
      maxRecommendationScore: maxRecommendationScore,
      actionLabel: actionLabel,
      positiveFactors: positives,
      riskCaps: risks,
    );
  }

  static int capRecommendationScore(
    int currentScore,
    ShortTermScoreResult shortTerm,
  ) {
    return currentScore.clamp(1, shortTerm.maxRecommendationScore).toInt();
  }

  static double _weightedStrength(List<SignalItem> signals) {
    return signals.fold<double>(0, (sum, signal) {
      final durationWeight = switch (signal.duration) {
        SignalDuration.shortTerm => 1.2,
        SignalDuration.mediumTerm => 0.8,
        SignalDuration.longTerm => 0.4,
        null => 0.8,
      };
      final confidenceWeight =
          (signal.confidence?.clamp(0.4, 1.0) ?? 0.8).toDouble();
      return sum + signal.strength * durationWeight * confidenceWeight;
    });
  }

  static double _scoreRecentPrice(
    List<HistoryKline> data,
    List<String> positives,
    List<String> risks,
  ) {
    if (data.length < 4) return 0;
    final last = data.last;
    final ref = data[data.length - 4].close;
    if (ref <= 0) return 0;
    final change3d = (last.close / ref - 1) * 100;
    if (change3d > 1.5 && change3d <= 8) {
      positives.add('近3日价格转强');
      return 0.8;
    }
    if (change3d > 12) {
      risks.add('近3日涨幅过快，短线追高风险');
      return -0.8;
    }
    if (change3d < -3) {
      risks.add('近3日价格走弱');
      return -1.2;
    }
    return 0;
  }

  static double _scoreVolumePrice(
    List<HistoryKline> data,
    List<String> positives,
    List<String> risks,
  ) {
    final last = data.last;
    if (last.volMa5 <= 0) return 0;
    final volRatio = last.volume / last.volMa5;
    if (last.close >= last.open) {
      if (volRatio >= 1.4) {
        positives.add('放量上涨确认');
        return 0.8;
      }
      if (volRatio < 0.7) {
        risks.add('上涨缩量，持续性不足');
        return -0.6;
      }
    } else if (volRatio >= 1.3) {
      risks.add('放量下跌，抛压偏大');
      return -1.0;
    }
    return 0;
  }

  static double _scoreQuote(
    QuoteData? quote,
    List<String> positives,
    List<String> risks,
  ) {
    if (quote == null || quote.price <= 0) return 0;
    var score = 0.0;
    final cp = quote.changePct;
    if (cp > 2 && cp <= 5) {
      positives.add('当日温和上涨');
      score += 0.9;
    } else if (cp > 0 && cp <= 2) {
      score += 0.4;
    } else if (cp > 5 && cp <= 8) {
      risks.add('当日涨幅偏大，追高需控制仓位');
      score -= 0.3;
    } else if (cp > 8) {
      risks.add('当日大涨，短线追高风险高');
      score -= 1.2;
    } else if (cp < -2) {
      risks.add('当日走弱');
      score -= cp < -5 ? 1.6 : 0.9;
    }

    final flowRate = quote.mainNetFlowRate;
    if (flowRate > 5) {
      positives.add('主力资金明显净流入');
      score += 1.1;
    } else if (flowRate > 2) {
      positives.add('主力资金净流入');
      score += 0.7;
    } else if (flowRate < -6) {
      risks.add('主力资金大幅净流出');
      score -= 1.4;
    } else if (flowRate < -3) {
      risks.add('主力资金净流出');
      score -= 1.0;
    }

    if (quote.turnover >= 2 && quote.turnover <= 8) {
      score += 0.3;
    } else if (quote.turnover > 15) {
      risks.add('换手率过高，分歧偏大');
      score -= 0.8;
    } else if (quote.turnover > 0 && quote.turnover < 0.8) {
      risks.add('换手率过低，短线流动性不足');
      score -= 0.5;
    }

    return score;
  }

  static double _scoreVolatility(
    HistoryKline last,
    QuoteData? quote,
    List<String> risks,
  ) {
    var score = 0.0;
    if (last.atr14 > 0 && last.close > 0) {
      final atrPct = last.atr14 / last.close * 100;
      if (atrPct >= 1.5 && atrPct <= 5) {
        score += 0.3;
      } else if (atrPct > 8) {
        risks.add('ATR波动过高');
        score -= 1.0;
      } else if (atrPct < 1) {
        score -= 0.3;
      }
    }
    if (quote != null && quote.amplitude > 8) {
      risks.add('当日振幅过大');
      score -= 0.5;
    }
    return score;
  }

  static int _riskCapFromQuote(
    QuoteData quote,
    List<HistoryKline> data,
    List<String> risks,
  ) {
    var cap = 10;
    final limitThreshold = _limitUpThreshold(quote.code);
    if (quote.changePct >= limitThreshold) {
      risks.add('已接近涨停，短线不宜追高');
      cap = 5;
    } else if (quote.changePct > 7) {
      risks.add('当日涨幅过大，短线追高风险');
      cap = 6;
    } else if (quote.changePct > 5) {
      cap = 7;
    }

    if (data.length >= 6) {
      final ref = data[data.length - 6].close;
      if (ref > 0) {
        final change5d = (data.last.close / ref - 1) * 100;
        if (change5d > 15) {
          risks.add('近5日涨幅过大，回撤风险升高');
          cap = cap > 6 ? 6 : cap;
        }
      }
    }

    if (quote.pe <= 0) {
      risks.add('亏损或估值数据异常，仅适合作为短线风险博弈');
      cap = cap > 8 ? 8 : cap;
    } else if (quote.pe >= 80) {
      risks.add('估值偏高，短线仓位需受限');
      cap = cap > 7 ? 7 : cap;
    }

    if (quote.turnover > 20) {
      cap = cap > 7 ? 7 : cap;
    }

    return cap;
  }

  static int _lowerCap(int current, int candidate) {
    return current < candidate ? current : candidate;
  }

  static double _limitUpThreshold(String code) {
    final normalized = code.replaceFirst(RegExp(r'^(sh|sz|bj)'), '');
    if (normalized.startsWith('8') || normalized.startsWith('43')) return 29.0;
    if (normalized.startsWith('688') || normalized.startsWith('30')) {
      return 19.0;
    }
    return 9.5;
  }
}
