import '../models/stock_models.dart';

class NextDayPredictionResult {
  final double upProbability;
  final double downProbability;
  final double neutralProbability;
  final int sampleCount;
  final String description;
  final Map<String, String> featureBins;

  NextDayPredictionResult({
    required this.upProbability,
    required this.downProbability,
    required this.neutralProbability,
    required this.sampleCount,
    required this.description,
    required this.featureBins,
  });

  Map<String, dynamic> toJson() {
    return {
      'up_probability': upProbability,
      'down_probability': downProbability,
      'neutral_probability': neutralProbability,
      'sample_count': sampleCount,
      'description': description,
      'feature_bins': featureBins,
    };
  }
}

class NextDayPredictor {
  static const int minSampleSize = 15;
  static const int maxLookback = 200;
  static const double neutralThreshold = 0.5;

  static const Map<String, double> _featureWeights = {
    'adx': 1.5,
    'macd_cross': 1.5,
    'macd_hist': 1.2,
    'kdj': 1.2,
    'rsi': 1.0,
    'volume': 0.8,
    'ma5_ma10': 0.8,
  };

  static NextDayPredictionResult predict(
      List<HistoryKline> data, QuoteData? quote) {
    if (data.length < 30) {
      return NextDayPredictionResult(
        upProbability: 0.5,
        downProbability: 0.5,
        neutralProbability: 0.0,
        sampleCount: 0,
        description: '历史数据不足，预测结果中性',
        featureBins: {},
      );
    }

    final last = data[data.length - 1];
    final lookbackData = data.length > maxLookback
        ? data.sublist(data.length - maxLookback - 1)
        : data;

    final currentFeatures = _extractFeatures(last);
    final historicalMatches =
        _findSimilarHistoricalPatterns(lookbackData, currentFeatures);

    if (historicalMatches.isEmpty) {
      return NextDayPredictionResult(
        upProbability: 0.5,
        downProbability: 0.5,
        neutralProbability: 0.0,
        sampleCount: 0,
        description: '未找到相似历史模式，预测结果中性',
        featureBins: currentFeatures,
      );
    }

    final weightedMatches =
        _applyTimeDecay(historicalMatches, lookbackData.length);

    double upWeight = 0;
    double downWeight = 0;
    double neutralWeight = 0;
    for (final match in weightedMatches) {
      final weight = match.matchScore.clamp(0.05, 1.0).toDouble();
      if (match.nextChangePct > neutralThreshold) {
        upWeight += weight;
      } else if (match.nextChangePct < -neutralThreshold) {
        downWeight += weight;
      } else {
        neutralWeight += weight;
      }
    }
    final total = weightedMatches.length;
    final totalWeight = upWeight + downWeight + neutralWeight;

    var upProb = totalWeight > 0 ? upWeight / totalWeight : 0.5;
    var downProb = totalWeight > 0 ? downWeight / totalWeight : 0.5;
    var neutralProb = totalWeight > 0 ? neutralWeight / totalWeight : 0.0;

    final sampleConfidence = (total / minSampleSize).clamp(0.0, 1.0).toDouble();
    if (sampleConfidence < 1.0) {
      upProb = 0.5 * (1 - sampleConfidence) + upProb * sampleConfidence;
      downProb = 0.5 * (1 - sampleConfidence) + downProb * sampleConfidence;
      neutralProb = neutralProb * sampleConfidence;
    }

    String description;
    if (total < minSampleSize) {
      description = '相似样本不足($total/$minSampleSize)，预测已降级为中性参考';
    } else if (upProb >= 0.55) {
      description = '次日上涨概率较高(${upProb.toStringAsFixed(2)})，基于$total个相似历史模式';
    } else if (downProb >= 0.55) {
      description = '次日下跌概率较高(${downProb.toStringAsFixed(2)})，基于$total个相似历史模式';
    } else if (neutralProb >= 0.3) {
      description =
          '次日震荡概率较高(${neutralProb.toStringAsFixed(2)})，基于$total个相似历史模式';
    } else {
      description = '次日涨跌概率中性，基于$total个相似历史模式';
    }

    return NextDayPredictionResult(
      upProbability: upProb,
      downProbability: downProb,
      neutralProbability: neutralProb,
      sampleCount: total,
      description: description,
      featureBins: currentFeatures,
    );
  }

  static Map<String, String> _extractFeatures(HistoryKline kline) {
    final features = <String, String>{};

    if (kline.rsi6.isFinite && kline.rsi6 >= 0 && kline.rsi6 <= 100) {
      if (kline.rsi6 >= 70) {
        features['rsi'] = '超买';
      } else if (kline.rsi6 >= 50) {
        features['rsi'] = '偏强';
      } else if (kline.rsi6 >= 30) {
        features['rsi'] = '偏弱';
      } else {
        features['rsi'] = '超卖';
      }
    }

    if (kline.macdHist.isFinite) {
      if (kline.macdHist > 0.001) {
        features['macd_hist'] = '红柱';
      } else if (kline.macdHist < -0.001) {
        features['macd_hist'] = '绿柱';
      } else {
        features['macd_hist'] = '零轴';
      }
    }

    if (kline.macdDif.isFinite && kline.macdDea.isFinite) {
      if (kline.macdDif > kline.macdDea) {
        features['macd_cross'] = '金叉区域';
      } else {
        features['macd_cross'] = '死叉区域';
      }
    }

    if (kline.k.isFinite && kline.k >= 0 && kline.k <= 100) {
      if (kline.k >= 80) {
        features['kdj'] = '超买';
      } else if (kline.k >= 50) {
        features['kdj'] = '偏多';
      } else if (kline.k >= 20) {
        features['kdj'] = '偏空';
      } else {
        features['kdj'] = '超卖';
      }
    }

    if (kline.volMa5 > 0 && kline.volume > 0) {
      final volRatio = kline.volume / kline.volMa5;
      if (volRatio >= 1.5) {
        features['volume'] = '放量';
      } else if (volRatio >= 1.0) {
        features['volume'] = '正常';
      } else {
        features['volume'] = '缩量';
      }
    }

    if (kline.ma5 > 0 && kline.ma10 > 0) {
      features['ma5_ma10'] = kline.ma5 > kline.ma10 ? 'MA5上穿' : 'MA5下穿';
    }

    if (kline.adx14.isFinite && kline.adx14 >= 0 && kline.adx14 <= 100) {
      if (kline.adx14 >= 25) {
        features['adx'] = '趋势明确';
      } else if (kline.adx14 >= 20) {
        features['adx'] = '趋势形成';
      } else {
        features['adx'] = '盘整';
      }
    }

    return features;
  }

  static List<_HistoricalMatch> _findSimilarHistoricalPatterns(
      List<HistoryKline> data, Map<String, String> targetFeatures) {
    final matches = <_HistoricalMatch>[];

    for (int i = 0; i < data.length - 1; i++) {
      final historicalFeatures = _extractFeatures(data[i]);
      final matchScore =
          _calculateWeightedMatchScore(historicalFeatures, targetFeatures);

      if (matchScore >= 0.5) {
        final nextDay = data[i + 1];
        final prevClose = data[i].close;
        final nextChangePct = prevClose > 0
            ? ((nextDay.close - prevClose) / prevClose * 100).toDouble()
            : 0.0;

        matches.add(_HistoricalMatch(
          matchScore: matchScore,
          nextChangePct: nextChangePct,
          index: i,
        ));
      }
    }

    matches.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return matches.take(50).toList();
  }

  static double _calculateWeightedMatchScore(
      Map<String, String> historical, Map<String, String> target) {
    if (target.isEmpty) return 0.5;

    double totalWeight = 0;
    double matchedWeight = 0;

    for (final key in target.keys) {
      final weight = _featureWeights[key] ?? 1.0;
      totalWeight += weight;

      if (historical.containsKey(key) && historical[key] == target[key]) {
        matchedWeight += weight;
      }
    }

    return totalWeight > 0 ? matchedWeight / totalWeight : 0.0;
  }

  static List<_HistoricalMatch> _applyTimeDecay(
      List<_HistoricalMatch> matches, int totalDataLength) {
    if (matches.isEmpty) return matches;

    const decayFactor = 0.002;

    return matches.map((m) {
      final ageFactor =
          1.0 - (totalDataLength - m.index) / totalDataLength * decayFactor;
      return _HistoricalMatch(
        matchScore: m.matchScore * ageFactor.clamp(0.8, 1.0),
        nextChangePct: m.nextChangePct,
        index: m.index,
      );
    }).toList();
  }
}

class _HistoricalMatch {
  final double matchScore;
  final double nextChangePct;
  final int index;

  _HistoricalMatch({
    required this.matchScore,
    required this.nextChangePct,
    required this.index,
  });
}
