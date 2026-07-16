import '../models/stock_models.dart';
import '../models/short_term_decision.dart';

class WeightCalibrationResult {
  final Map<String, double> strategyAdjustments;
  final Map<String, Map<String, double>> regimeAdjustments;
  final DateTime calibratedAt;
  final int sampleCount;
  final bool isValid;

  const WeightCalibrationResult({
    required this.strategyAdjustments,
    required this.regimeAdjustments,
    required this.calibratedAt,
    required this.sampleCount,
    required this.isValid,
  });
}

class WeightCalibrator {
  static const int kMinSampleForCalibration = 30;
  static const int kMinSamplePerStrategy = 10;

  static WeightCalibrationResult calibrate(
    List<DecisionSnapshotRecord> recentSnapshots, {
    int lookbackDays = 30,
  }) {
    final cutoff = DateTime.now().subtract(Duration(days: lookbackDays));
    final recent = recentSnapshots.where(
      (r) => r.signalTradeDate.isAfter(cutoff),
    ).toList();

    final byStrategy = <String, List<DecisionSnapshotRecord>>{};
    for (final r in recent) {
      final strategyId = r.primaryStrategyId ?? 'unknown';
      byStrategy.putIfAbsent(strategyId, () => []).add(r);
    }

    final adjustments = <String, double>{};
    for (final entry in byStrategy.entries) {
      if (entry.value.length < kMinSamplePerStrategy) {
        adjustments[entry.key] = 1.0;
        continue;
      }
      final winRate = _winRateFromSnapshots(entry.value);
      if (winRate > 0.6) {
        adjustments[entry.key] = (1.0 + (winRate - 0.6) * 1.5).clamp(0.5, 1.5);
      } else if (winRate < 0.4) {
        adjustments[entry.key] = (0.5 + winRate * 1.25).clamp(0.5, 1.5);
      } else {
        adjustments[entry.key] = 1.0;
      }
    }

    final regimeAdjustments = <String, Map<String, double>>{};
    for (final regime in MarketRegime.values) {
      final regimeRows = recent.where(
        (r) => r.marketRegime == regime,
      ).toList();
      if (regimeRows.length < kMinSamplePerStrategy) continue;

      final regimeByStrategy = <String, List<DecisionSnapshotRecord>>{};
      for (final r in regimeRows) {
        final sid = r.primaryStrategyId ?? 'unknown';
        regimeByStrategy.putIfAbsent(sid, () => []).add(r);
      }

      final regimeAdj = <String, double>{};
      for (final entry in regimeByStrategy.entries) {
        if (entry.value.length < kMinSamplePerStrategy) {
          regimeAdj[entry.key] = 1.0;
          continue;
        }
        final winRate = _winRateFromSnapshots(entry.value);
        if (winRate > 0.6) {
          regimeAdj[entry.key] = (1.0 + (winRate - 0.6) * 1.5).clamp(0.5, 1.5);
        } else if (winRate < 0.4) {
          regimeAdj[entry.key] = (0.5 + winRate * 1.25).clamp(0.5, 1.5);
        } else {
          regimeAdj[entry.key] = 1.0;
        }
      }
      regimeAdjustments[regime.name] = regimeAdj;
    }

    return WeightCalibrationResult(
      strategyAdjustments: adjustments,
      regimeAdjustments: regimeAdjustments,
      calibratedAt: DateTime.now(),
      sampleCount: recent.length,
      isValid: recent.length >= kMinSampleForCalibration,
    );
  }

  static double _winRateFromSnapshots(List<DecisionSnapshotRecord> snapshots) {
    if (snapshots.isEmpty) return 0.5;
    final bullish = snapshots.where(
        (s) => s.direction == RecommendationDirection.bullish).toList();
    if (bullish.isEmpty) return 0.5;
    final wins = bullish.where((s) => s.directionScore > 0).length;
    return wins / bullish.length;
  }
}
