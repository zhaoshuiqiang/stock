import '../models/stock_models.dart';

class RecommendationCalibrationResult {
  final int score;
  final String reason;

  const RecommendationCalibrationResult({
    required this.score,
    this.reason = '',
  });
}

class RecommendationCalibrator {
  static RecommendationCalibrationResult calibrateScore({
    required int score,
    required List<HistoryKline> data,
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    double? currentChangePct,
  }) {
    if (data.isEmpty) {
      return RecommendationCalibrationResult(score: score);
    }

    final buyStrength = _weightedStrength(buySignals);
    final sellStrength = _weightedStrength(sellSignals);

    if (score >= 6) {
      final margin = buyStrength - sellStrength;
      final weakBuyEvidence =
          buySignals.length < 2 && !_hasBullTrend(data.last);
      final conflictThreshold = score >= 7 ? 0.8 : 0.5;
      final hasConflict = sellStrength > 0 && margin < conflictThreshold;
      if (hasConflict || (score == 6 && weakBuyEvidence)) {
        final capped = score >= 7 ? 6 : 5;
        return RecommendationCalibrationResult(
          score: capped,
          reason: '方向校准：买入证据偏弱或存在卖出信号冲突，降级为观望/谨慎参与',
        );
      }
    }

    if (score <= 3) {
      final sellMargin = sellStrength - buyStrength;
      final hasConflict = buyStrength > 0 && sellMargin < 2.0;
      final reboundRisk = _isSharpDecline(data, currentChangePct) &&
          _hasReboundEvidence(data.last, buySignals, buyStrength);
      if (hasConflict || reboundRisk) {
        return const RecommendationCalibrationResult(
          score: 4,
          reason: '方向校准：大跌后存在超跌反弹或多空冲突风险，卖出建议降级为偏空观望',
        );
      }
    }

    return RecommendationCalibrationResult(score: score);
  }

  static double _weightedStrength(List<SignalItem> signals) {
    return signals.fold<double>(0, (sum, signal) {
      final normalizedStrength = _normalizeStrength(signal.strength);
      final durationWeight = switch (signal.duration) {
        SignalDuration.shortTerm => 1.2,
        SignalDuration.mediumTerm => 0.8,
        SignalDuration.longTerm => 0.4,
        null => 0.8,
      };
      final confidenceWeight =
          (signal.confidence?.clamp(0.4, 1.0) ?? 0.8).toDouble();
      return sum + normalizedStrength * durationWeight * confidenceWeight;
    });
  }

  static double _normalizeStrength(int strength) {
    if (strength <= 0) return 0;
    if (strength <= 3) return (strength / 3).clamp(0.0, 1.0).toDouble();
    return (strength / 100).clamp(0.0, 1.0).toDouble();
  }

  static bool _hasBullTrend(HistoryKline last) {
    final bullMa = last.ma5 > 0 &&
        last.ma10 > 0 &&
        last.ma20 > 0 &&
        last.ma5 > last.ma10 &&
        last.ma10 > last.ma20;
    final priceAboveMa = last.ma5 > 0 && last.close > last.ma5;
    final trendConfirmed = last.adx14 > 25 && priceAboveMa;
    return bullMa || trendConfirmed;
  }

  static bool _isSharpDecline(
    List<HistoryKline> data,
    double? currentChangePct,
  ) {
    if (currentChangePct != null && currentChangePct <= -3.0) return true;
    if (data.length < 4) return false;
    final ref = data[data.length - 4].close;
    if (ref <= 0) return false;
    final change3d = (data.last.close / ref - 1) * 100;
    return change3d <= -3.0;
  }

  static bool _hasReboundEvidence(
    HistoryKline last,
    List<SignalItem> buySignals,
    double buyStrength,
  ) {
    if (buySignals.isEmpty) return false;
    final oversoldRsi = last.rsi6 > 0 && last.rsi6 < 35;
    final oversoldWr = last.wr14 != null && last.wr14! > 80;
    final negativeBias = last.bias6 < -3;
    return oversoldRsi || oversoldWr || negativeBias || buyStrength >= 0.5;
  }
}
