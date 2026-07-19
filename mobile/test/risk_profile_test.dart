import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
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
  tearDown(() => ScoringConfig.riskProfile = RiskProfile.balanced);

  test('balanced is identity: marginal strong buy stays 强烈买入', () {
    ScoringConfig.riskProfile = RiskProfile.balanced;
    // ds=60 -> strongBullish; quality 72 >= default gate 70 -> passes.
    final r = RecommendationPolicy.evaluate(
        _decision(directionScore: 60, tradeQualityScore: 72));
    expect(r.label, '强烈买入');
  });

  test('conservative tightens gates: same case downgraded to 偏多观望', () {
    ScoringConfig.riskProfile = RiskProfile.conservative;
    // strong-buy quality gate becomes 78; 72 < 78 -> gated down.
    final r = RecommendationPolicy.evaluate(
        _decision(directionScore: 60, tradeQualityScore: 72));
    expect(r.label, '偏多观望');
    expect(r.actionable, isFalse);
  });

  test('aggressive loosens gates: a balanced-gated case becomes 强烈买入', () {
    // Balanced: quality 64 < 70 gate -> gated to 偏多观望.
    ScoringConfig.riskProfile = RiskProfile.balanced;
    final balanced = RecommendationPolicy.evaluate(
        _decision(directionScore: 60, tradeQualityScore: 64));
    expect(balanced.label, '偏多观望');

    // Aggressive: quality gate becomes 62 -> 64 >= 62 passes.
    ScoringConfig.riskProfile = RiskProfile.aggressive;
    final aggressive = RecommendationPolicy.evaluate(
        _decision(directionScore: 60, tradeQualityScore: 64));
    expect(aggressive.label, '强烈买入');
  });
}
