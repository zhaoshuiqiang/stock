import 'dart:math' as math;

import '../models/stock_models.dart';
import 'next_session_feature_extractor.dart';
import 'next_session_prediction.dart';
import 'next_day_predictor.dart';

class NextSessionPredictor {
  static const int minSampleSize = 8;

  static NextSessionPrediction predict(
    List<HistoryKline> data, {
    int? index,
    int minSamples = minSampleSize,
    int maxSamples = 50,
  }) {
    if (data.length < 3) {
      final features = data.isEmpty
          ? null
          : NextSessionFeatureExtractor.extract(data, index: data.length - 1);
      return NextSessionPrediction.neutral(
        scenarioTags: features?.scenarioTags ?? const [],
        riskWarnings: features?.riskWarnings ?? const [],
      );
    }

    final currentIndex = index ?? data.length - 1;
    final features =
        NextSessionFeatureExtractor.extract(data, index: currentIndex);
    final candidates = <_ComparableSample>[];

    for (var i = 1; i < currentIndex; i++) {
      final current = data[i];
      if (current.close <= 0) continue;
      final sampleFeatures =
          NextSessionFeatureExtractor.extract(data, index: i);
      var similarity = _similarity(features, sampleFeatures);
      final timeDecay = currentIndex > 0
          ? (1.0 - (currentIndex - i) / currentIndex * 0.3).clamp(0.7, 1.0)
          : 1.0;
      similarity *= timeDecay;
      if (!similarity.isFinite || similarity <= 0) continue;

      final next = data[i + 1];
      candidates.add(_ComparableSample(
        similarity: similarity,
        nextOpenReturn: (next.open / current.close - 1) * 100,
        nextCloseReturn: (next.close / current.close - 1) * 100,
      ));
    }

    candidates.sort((a, b) => b.similarity.compareTo(a.similarity));
    // v4.12: K-nearest with a legacy-radius preference. Keep the >=0.5
    // neighbor set when it already has enough samples (byte-identical to the
    // old radius filter); otherwise fall back to the top-K nearest so the
    // indicator still yields a meaningful similarity-weighted estimate
    // instead of the degenerate 50/50 neutral. On normal-length history few
    // bars clear the strict 0.5 radius, which left sampleCount stuck at 0.
    final strong =
        candidates.where((s) => s.similarity >= 0.5).toList(growable: false);
    final selected = strong.length >= minSamples ? strong : candidates;
    final samples = selected.take(maxSamples).toList(growable: false);
    if (samples.length < minSamples) {
      final sampleFactor = samples.length / minSamples;
      return NextSessionPrediction.neutral(
        neutralProbability: 0,
        confidence: (sampleFactor * 0.25).clamp(0.0, 0.25),
        sampleCount: samples.length,
        scenarioTags: features.scenarioTags,
        riskWarnings: features.riskWarnings,
      );
    }

    final totalWeight = samples.fold<double>(0, (sum, s) => sum + s.similarity);
    final openUpWeight = samples
        .where((s) => s.nextOpenReturn > 0)
        .fold<double>(0, (sum, s) => sum + s.similarity);
    final closeUpWeight = samples
        .where((s) => s.nextCloseReturn > 0)
        .fold<double>(0, (sum, s) => sum + s.similarity);
    final downsideWeight = samples
        .where((s) => s.nextCloseReturn < -0.5)
        .fold<double>(0, (sum, s) => sum + s.similarity);
    final neutralWeight = samples
        .where((s) => s.nextCloseReturn.abs() < 0.5)
        .fold<double>(0, (sum, s) => sum + s.similarity);
    final expectedReturn = samples.fold<double>(
          0,
          (sum, s) => sum + s.nextCloseReturn * s.similarity,
        ) /
        totalWeight;

    var nextOpenUpProbability =
        _shrinkProbability(openUpWeight, totalWeight, minSamples);
    var nextCloseUpProbability =
        _shrinkProbability(closeUpWeight, totalWeight, minSamples);
    var downsideRiskProbability =
        _shrinkProbability(downsideWeight, totalWeight, minSamples);
    var neutralProbability =
        _shrinkProbability(neutralWeight, totalWeight, minSamples);
    var confidence =
        _confidence(nextCloseUpProbability, samples.length, minSamples);

    final riskWarnings = {...features.riskWarnings};
    final isChaseRisk = features.scenarioTags.contains('高位回调风险') ||
        features.scenarioTags.contains('长上影分歧') ||
        features.scenarioTags.contains('放量滞涨');
    if (isChaseRisk && features.changePct > 5) {
      nextCloseUpProbability = math.min(nextCloseUpProbability, 0.55);
      downsideRiskProbability = math.max(downsideRiskProbability, 0.45);
      confidence = math.min(confidence, 0.55);
      riskWarnings.add('不追高');
    }
    if (features.scenarioTags.contains('缩量上涨不追')) {
      confidence = math.min(confidence, 0.6);
      riskWarnings.add('量能不足');
    }

    return NextSessionPrediction(
      nextOpenUpProbability: _clampProbability(nextOpenUpProbability),
      nextCloseUpProbability: _clampProbability(nextCloseUpProbability),
      expectedNextCloseReturn: expectedReturn,
      downsideRiskProbability: _clampProbability(downsideRiskProbability),
      neutralProbability: _clampProbability(neutralProbability),
      confidence: confidence.clamp(0.0, 0.95),
      sampleCount: samples.length,
      scenarioTags: features.scenarioTags,
      riskWarnings: riskWarnings.toList(growable: false),
    );
  }

  static double _similarity(NextSessionFeatures a, NextSessionFeatures b) {
    var distance = 0.0;
    distance += (a.changePct - b.changePct).abs() / 6 * 1.6;
    distance += (a.closePosition - b.closePosition).abs() * 1.4;
    distance += (a.upperShadowRatio - b.upperShadowRatio).abs() * 1.1;
    distance += (a.lowerShadowRatio - b.lowerShadowRatio).abs() * 0.8;
    distance += (_safeLogRatio(a.volumeRatio5, b.volumeRatio5)).abs() * 0.9;
    distance += (a.return5 - b.return5).abs() / 12 * 0.8;
    distance += (a.rsi6 - b.rsi6).abs() / 100 * 0.4;
    distance += (a.macdHist - b.macdHist).abs() / 5 * 0.3;
    distance += (a.volatility20 - b.volatility20).abs() / 5 * 0.4;
    distance += _featureBinDistance(a.featureBins, b.featureBins);
    return (1 / (1 + distance)).clamp(0.0, 1.0);
  }

  static double _featureBinDistance(
      Map<String, String> a, Map<String, String> b) {
    const binWeights = <String, double>{
      'adx': 1.5,
      'macd_cross': 1.5,
      'macd_hist': 1.2,
      'kdj': 1.2,
      'rsi': 1.0,
      'volume': 0.8,
      'ma5_ma10': 0.8,
    };
    const totalBinWeight = 8.0;
    var binDistance = 0.0;
    for (final key in binWeights.keys) {
      if (a.containsKey(key) && b.containsKey(key)) {
        if (a[key] != b[key]) {
          binDistance += binWeights[key]!;
        }
      }
    }
    return binDistance / totalBinWeight;
  }

  static double _shrinkProbability(
    double positiveWeight,
    double totalWeight,
    int minSamples,
  ) {
    final priorWeight = minSamples.toDouble();
    return (positiveWeight + 0.5 * priorWeight) / (totalWeight + priorWeight);
  }

  static double _confidence(
      double probability, int sampleCount, int minSamples) {
    final sampleFactor = (sampleCount / (minSamples * 2)).clamp(0.0, 1.0);
    final edge = ((probability - 0.5).abs() * 2).clamp(0.0, 1.0);
    return (sampleFactor * (0.35 + edge * 0.55)).clamp(0.0, 0.95);
  }

  static double _safeLogRatio(double a, double b) {
    final safeA = a <= 0 ? 0.01 : a;
    final safeB = b <= 0 ? 0.01 : b;
    return math.log(safeA / safeB);
  }

  static double _clampProbability(double value) => value.clamp(0.0, 1.0);
}

class _ComparableSample {
  final double similarity;
  final double nextOpenReturn;
  final double nextCloseReturn;

  const _ComparableSample({
    required this.similarity,
    required this.nextOpenReturn,
    required this.nextCloseReturn,
  });
}
