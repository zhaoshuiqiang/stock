import 'scoring_config.dart';

/// Calibratable recommendation thresholds for the live v3 policy (plan P2.2).
///
/// Only the actionable magnitude bands (cautious / bullish / strong) and the
/// execution-gate minimums are calibratable. The +/-12 neutral band that
/// determines direction is intentionally NOT calibrated here so that direction
/// determination (RecommendationPolicy._directionOf) stays consistent with the
/// level mapping. Bearish bands mirror the bullish magnitudes (symmetric).
class RecommendationThresholds {
  final double cautiousBullish; // default 20
  final double bullish; // default 35
  final double strongBullish; // default 55

  final double strongBullishQualityMin; // 70
  final double strongBullishRiskMax; // 45
  final double strongBullishConfidenceMin; // 65
  final double bullishQualityMin; // 60
  final double bullishRiskMax; // 60
  final double bullishConfidenceMin; // 55
  final double cautiousBullishQualityMin; // 55
  final double cautiousBullishRiskMax; // 70
  final double bearishConfidenceMin; // 55

  const RecommendationThresholds({
    required this.cautiousBullish,
    required this.bullish,
    required this.strongBullish,
    required this.strongBullishQualityMin,
    required this.strongBullishRiskMax,
    required this.strongBullishConfidenceMin,
    required this.bullishQualityMin,
    required this.bullishRiskMax,
    required this.bullishConfidenceMin,
    required this.cautiousBullishQualityMin,
    required this.cautiousBullishRiskMax,
    required this.bearishConfidenceMin,
  });

  /// The current (pre-calibration) production values — must match the inline
  /// constants historically used by RecommendationPolicy.
  static const RecommendationThresholds defaults = RecommendationThresholds(
    cautiousBullish: 20.0,
    bullish: 35.0,
    strongBullish: 55.0,
    strongBullishQualityMin: 70.0,
    strongBullishRiskMax: 45.0,
    strongBullishConfidenceMin: 65.0,
    bullishQualityMin: 60.0,
    bullishRiskMax: 60.0,
    bullishConfidenceMin: 55.0,
    cautiousBullishQualityMin: 55.0,
    cautiousBullishRiskMax: 70.0,
    bearishConfidenceMin: 55.0,
  );

  RecommendationThresholds copyWith({
    double? cautiousBullish,
    double? bullish,
    double? strongBullish,
  }) {
    return RecommendationThresholds(
      cautiousBullish: cautiousBullish ?? this.cautiousBullish,
      bullish: bullish ?? this.bullish,
      strongBullish: strongBullish ?? this.strongBullish,
      strongBullishQualityMin: strongBullishQualityMin,
      strongBullishRiskMax: strongBullishRiskMax,
      strongBullishConfidenceMin: strongBullishConfidenceMin,
      bullishQualityMin: bullishQualityMin,
      bullishRiskMax: bullishRiskMax,
      bullishConfidenceMin: bullishConfidenceMin,
      cautiousBullishQualityMin: cautiousBullishQualityMin,
      cautiousBullishRiskMax: cautiousBullishRiskMax,
      bearishConfidenceMin: bearishConfidenceMin,
    );
  }

  /// P3: apply the user's risk appetite to execution-gate strictness. Band
  /// boundaries are unchanged; only gate minimums move. `balanced` == identity.
  RecommendationThresholds forRiskProfile(RiskProfile p) {
    final (dq, dr, dc) = switch (p) {
      RiskProfile.conservative => (8.0, -8.0, 8.0),
      RiskProfile.balanced => (0.0, 0.0, 0.0),
      RiskProfile.aggressive => (-8.0, 8.0, -8.0),
    };
    if (dq == 0 && dr == 0 && dc == 0) return this;
    double q(double v) => (v + dq).clamp(0.0, 100.0).toDouble();
    double r(double v) => (v + dr).clamp(0.0, 100.0).toDouble();
    double c(double v) => (v + dc).clamp(0.0, 100.0).toDouble();
    return RecommendationThresholds(
      cautiousBullish: cautiousBullish,
      bullish: bullish,
      strongBullish: strongBullish,
      strongBullishQualityMin: q(strongBullishQualityMin),
      strongBullishRiskMax: r(strongBullishRiskMax),
      strongBullishConfidenceMin: c(strongBullishConfidenceMin),
      bullishQualityMin: q(bullishQualityMin),
      bullishRiskMax: r(bullishRiskMax),
      bullishConfidenceMin: c(bullishConfidenceMin),
      cautiousBullishQualityMin: q(cautiousBullishQualityMin),
      cautiousBullishRiskMax: r(cautiousBullishRiskMax),
      bearishConfidenceMin: bearishConfidenceMin,
    );
  }
}

/// Realized outcome statistics for one strength band, used to calibrate the
/// band boundary. [hitRate] in 0..1, [count] evaluated samples.
class BandOutcomeStat {
  final double hitRate;
  final int count;
  const BandOutcomeStat(this.hitRate, this.count);
}

/// Data-driven calibrator for [RecommendationThresholds] (plan P2.2).
///
/// Intuition: each actionable band promises a certain conviction. If a band's
/// realized hit rate is below its target, the boundary is RAISED (require a
/// higher directionScore to enter that band); if above target, it is LOWERED.
/// Adjustment is proportional, bounded by [maxShift], gated by a per-band
/// minimum sample count, and the final ordering (cautious < bullish < strong)
/// is always preserved. Insufficient data -> defaults (no change).
class RecommendationThresholdCalibrator {
  static const double maxShift = 8.0;
  static const int minBandSamples = 100;

  /// Target realized effective-hit rate per actionable strength band:
  /// band 1 = cautiousBullish (20-35), 2 = bullish (35-55), 3 = strong (55+).
  static const Map<int, double> targetHitRate = {1: 0.52, 2: 0.57, 3: 0.62};

  /// [bandStats] maps strength band (1/2/3) -> realized stats. Returns a
  /// calibrated [RecommendationThresholds] (band boundaries adjusted; gate
  /// minimums preserved).
  static RecommendationThresholds optimize(
    Map<int, BandOutcomeStat> bandStats, {
    RecommendationThresholds? defaults,
    double shiftGain = 40.0,
  }) {
    final base = defaults ?? RecommendationThresholds.defaults;

    double shiftFor(int band) {
      final stat = bandStats[band];
      final target = targetHitRate[band];
      if (stat == null || target == null || stat.count < minBandSamples) {
        return 0.0;
      }
      // hitRate below target -> positive shift (raise boundary, stricter).
      final deviation = target - stat.hitRate; // >0 means underperforming
      return (deviation * shiftGain).clamp(-maxShift, maxShift);
    }

    var cautious = base.cautiousBullish + shiftFor(1);
    var bullish = base.bullish + shiftFor(2);
    var strong = base.strongBullish + shiftFor(3);

    // Preserve strict ordering and the fixed neutral band (>12) so the mapping
    // remains monotonic: 12 < cautious < bullish < strong < 100.
    cautious = cautious.clamp(13.0, 80.0).toDouble();
    bullish = bullish.clamp(cautious + 1, 90.0).toDouble();
    strong = strong.clamp(bullish + 1, 99.0).toDouble();

    return base.copyWith(
      cautiousBullish: cautious,
      bullish: bullish,
      strongBullish: strong,
    );
  }
}
