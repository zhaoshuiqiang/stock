import '../models/stock_models.dart';

class MomentumPersistenceResult {
  final double persistenceScore;
  final double adxTrendScore;
  final double volumeConfirmScore;
  final double priceDeviationScore;
  final String description;

  MomentumPersistenceResult({
    required this.persistenceScore,
    required this.adxTrendScore,
    required this.volumeConfirmScore,
    required this.priceDeviationScore,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'persistence_score': persistenceScore,
      'adx_trend_score': adxTrendScore,
      'volume_confirm_score': volumeConfirmScore,
      'price_deviation_score': priceDeviationScore,
      'description': description,
    };
  }
}

class MomentumPersistenceAnalyzer {
  static MomentumPersistenceResult analyze(List<HistoryKline> data) {
    if (data.length < 10) {
      return MomentumPersistenceResult(
        persistenceScore: 0.5,
        adxTrendScore: 0.5,
        volumeConfirmScore: 0.5,
        priceDeviationScore: 0.5,
        description: '数据不足，动量持续性中性',
      );
    }

    final adxTrend = _analyzeAdxTrend(data);
    final volumeConfirm = _analyzeVolumeConfirm(data);
    final priceDeviation = _analyzePriceDeviation(data);

    final persistenceScore = (adxTrend * 0.4 + volumeConfirm * 0.3 + priceDeviation * 0.3).clamp(0.0, 1.0);

    final descriptions = <String>[];
    if (adxTrend > 0.7) descriptions.add('ADX上升，趋势加速');
    else if (adxTrend < 0.3) descriptions.add('ADX下降，趋势减弱');

    if (volumeConfirm > 0.7) descriptions.add('量能持续放大确认趋势');
    else if (volumeConfirm < 0.3) descriptions.add('量能萎缩，趋势缺乏量能支撑');

    if (priceDeviation > 0.7) descriptions.add('价格偏离度适中，趋势可持续');
    else if (priceDeviation < 0.3) descriptions.add('价格偏离过大，警惕均值回归');

    String description;
    if (persistenceScore > 0.7) {
      description = '动量持续性强(${persistenceScore.toStringAsFixed(2)})：${descriptions.join('；')}';
    } else if (persistenceScore < 0.3) {
      description = '动量持续性弱(${persistenceScore.toStringAsFixed(2)})：${descriptions.join('；')}';
    } else {
      description = '动量持续性中等(${persistenceScore.toStringAsFixed(2)})';
    }

    return MomentumPersistenceResult(
      persistenceScore: persistenceScore,
      adxTrendScore: adxTrend,
      volumeConfirmScore: volumeConfirm,
      priceDeviationScore: priceDeviation,
      description: description,
    );
  }

  static double _analyzeAdxTrend(List<HistoryKline> data) {
    if (data.length < 6) return 0.5;

    final recent3 = data.sublist(data.length - 3).map((k) => k.adx14).toList();
    final earlier3 = data.sublist(data.length - 6, data.length - 3).map((k) => k.adx14).toList();

    final recentAvg = recent3.fold(0.0, (a, b) => a + b) / 3;
    final earlierAvg = earlier3.fold(0.0, (a, b) => a + b) / 3;

    if (earlierAvg <= 0) return 0.5;

    final changeRate = (recentAvg - earlierAvg) / earlierAvg;

    if (changeRate > 0.15) return 0.9;
    if (changeRate > 0.05) return 0.7;
    if (changeRate > 0) return 0.55;
    if (changeRate > -0.05) return 0.45;
    if (changeRate > -0.15) return 0.3;
    return 0.1;
  }

  static double _analyzeVolumeConfirm(List<HistoryKline> data) {
    if (data.length < 6) return 0.5;

    final recent3 = data.sublist(data.length - 3);
    final earlier3 = data.sublist(data.length - 6, data.length - 3);

    double recentVolSum = 0;
    double earlierVolSum = 0;
    int validRecent = 0;
    int validEarlier = 0;

    for (final k in recent3) {
      if (k.volMa5 > 0) {
        recentVolSum += k.volume / k.volMa5;
        validRecent++;
      }
    }
    for (final k in earlier3) {
      if (k.volMa5 > 0) {
        earlierVolSum += k.volume / k.volMa5;
        validEarlier++;
      }
    }

    if (validRecent == 0 || validEarlier == 0) return 0.5;

    final recentAvg = recentVolSum / validRecent;
    final earlierAvg = earlierVolSum / validEarlier;

    final trendDirection = data.last.close > data[data.length - 6].close ? 1 : -1;

    if (trendDirection > 0) {
      if (recentAvg > earlierAvg * 1.3) return 0.9;
      if (recentAvg > earlierAvg * 1.1) return 0.7;
      if (recentAvg > earlierAvg * 0.9) return 0.5;
      if (recentAvg > earlierAvg * 0.7) return 0.3;
      return 0.1;
    } else {
      if (recentAvg < earlierAvg * 0.7) return 0.9;
      if (recentAvg < earlierAvg * 0.9) return 0.7;
      if (recentAvg < earlierAvg * 1.1) return 0.5;
      if (recentAvg < earlierAvg * 1.3) return 0.3;
      return 0.1;
    }
  }

  static double _analyzePriceDeviation(List<HistoryKline> data) {
    if (data.length < 20) return 0.5;

    final last = data.last;
    if (last.ma20 <= 0 || last.close <= 0) return 0.5;

    final deviation = (last.close - last.ma20).abs() / last.ma20;

    if (deviation < 0.02) return 0.7;
    if (deviation < 0.05) return 0.85;
    if (deviation < 0.08) return 0.6;
    if (deviation < 0.12) return 0.4;
    return 0.2;
  }
}