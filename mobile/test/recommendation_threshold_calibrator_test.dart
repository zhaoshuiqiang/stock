import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/analysis/recommendation_thresholds.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

ShortTermDecision _decision({
  required double directionScore,
  double tradeQualityScore = 90,
  double riskScore = 10,
  double evidenceConfidence = 90,
}) {
  return ShortTermDecision(
    directionScore: directionScore,
    tradeQualityScore: tradeQualityScore,
    riskScore: riskScore,
    evidenceConfidence: evidenceConfidence,
    calibrationByHorizon: const <int, CalibrationEstimate>{},
    direction: RecommendationDirection.neutral,
    marketRegime: MarketRegime.range,
    directionComponents: const <String, double>{},
    qualityComponents: const <String, double>{},
    riskComponents: const <String, double>{},
    dataQualityFlags: const <String>[],
    modelVersion: 'short-term-v3',
    rawComprehensiveScore: 6.0,
  );
}

void main() {
  tearDown(() {
    ScoringConfig.useCalibratedThresholds = false;
    RecommendationPolicy.applyThresholdOverride(null);
  });

  group('RecommendationThresholdCalibrator', () {
    test('insufficient samples keeps default thresholds', () {
      final r = RecommendationThresholdCalibrator.optimize(
        {3: const BandOutcomeStat(0.40, 10)},
      );
      expect(r.strongBullish, RecommendationThresholds.defaults.strongBullish);
    });

    test('underperforming band raises (tightens) its boundary', () {
      final r = RecommendationThresholdCalibrator.optimize(
        {3: const BandOutcomeStat(0.40, 500)}, // target 0.62 -> +8 (clamped)
      );
      expect(r.strongBullish, greaterThan(55.0));
      expect(r.strongBullish, lessThanOrEqualTo(55.0 + RecommendationThresholdCalibrator.maxShift));
    });

    test('overperforming band lowers (loosens) its boundary', () {
      final r = RecommendationThresholdCalibrator.optimize(
        {2: const BandOutcomeStat(0.80, 500)}, // above target 0.57
      );
      expect(r.bullish, lessThan(35.0));
    });

    test('strict ordering cautious < bullish < strong is always preserved', () {
      final r = RecommendationThresholdCalibrator.optimize({
        1: const BandOutcomeStat(0.30, 500), // pushes cautious up hard
        3: const BandOutcomeStat(0.90, 500), // pushes strong down hard
      });
      expect(r.cautiousBullish, lessThan(r.bullish));
      expect(r.bullish, lessThan(r.strongBullish));
      expect(r.cautiousBullish, greaterThan(12.0));
    });
  });

  group('RecommendationPolicy threshold flag gating', () {
    final override = RecommendationThresholds.defaults.copyWith(strongBullish: 45);

    test('flag OFF ignores override (ds=50 stays 买入)', () {
      ScoringConfig.useCalibratedThresholds = false;
      RecommendationPolicy.applyThresholdOverride(override);
      final r = RecommendationPolicy.evaluate(_decision(directionScore: 50));
      expect(r.label, '买入');
    });

    test('flag ON applies override (ds=50 becomes 强烈买入)', () {
      ScoringConfig.useCalibratedThresholds = true;
      RecommendationPolicy.applyThresholdOverride(override);
      final r = RecommendationPolicy.evaluate(_decision(directionScore: 50));
      expect(r.label, '强烈买入');
    });
  });
}
